# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP administrator assignments", type: :request do
  let(:superadmin) { create_user }
  let(:candidate) { create_user(mcp_admin: false) }
  let(:path) { "/admin/mcp_administrators" }

  before { skip "SolidusAdmin is optional" unless defined?(SolidusAdmin::Engine) }

  def headers
    {"X-Test-User" => @actor&.id.to_s}
  end

  def assign_csrf
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css('form[action="/admin/mcp_administrators"] input[name="authenticity_token"]')["value"]
  end

  def assign(user_id: candidate.id, csrf: assign_csrf)
    post path, headers: headers, params: {authenticity_token: csrf, administrator: {user_id: user_id}}
  end

  def update_assignment(assignment, enabled: "0", version: assignment.lock_version)
    get path, headers: headers
    form = Nokogiri::HTML(response.body).at_css("form[action=\"/admin/mcp_administrators/#{assignment.id}\"]")
    token = form.at_css('input[name="authenticity_token"]')["value"]
    patch "#{path}/#{assignment.id}", headers: headers, params: {authenticity_token: token,
                                                                 administrator: {enabled: enabled, lock_version: version.to_s}}
  end

  it "requires authentication and a configured superadministrator" do
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    [create_user(mcp_admin: false), create_user(superadmin: false)].each do |actor|
      @actor = actor
      get path, headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "denies forged role assignments even with a valid CSRF token" do
    @actor = superadmin
    csrf = assign_csrf
    [candidate, create_user(superadmin: false)].each do |actor|
      @actor = actor
      assign(user_id: actor.id, csrf: csrf)
      expect(response).to have_http_status(:forbidden)
    end
    expect(SolidusMcp::AdministratorChange.count).to eq(0)
    expect(SolidusMcp::Administration.role(candidate)).to eq(:user)
  end

  it "lets a superadministrator grant, revoke and restore an administrator assignment" do
    @actor = superadmin
    assign
    expect(response).to have_http_status(:see_other)
    assignment = SolidusMcp::Administrator.find_by!(user: candidate)
    expect(SolidusMcp::Administration.role(candidate)).to eq(:admin)
    update_assignment(assignment)
    expect(response).to have_http_status(:see_other)
    expect(SolidusMcp::Administration.role(candidate)).to eq(:user)
    update_assignment(assignment.reload, enabled: "1")
    expect(SolidusMcp::Administration.role(candidate)).to eq(:admin)
    expect(assignment.role_changes.order(:id).pluck(:actor_id, :enabled)).to eq([
      [superadmin.id, true], [superadmin.id, false], [superadmin.id, true]
    ])
  end

  it "cannot grant superadministrator status through the assignment form" do
    @actor = superadmin
    csrf = assign_csrf
    post path, headers: headers, params: {authenticity_token: csrf,
                                          administrator: {user_id: candidate.id, role: "superadmin", superadmin_emails: [candidate.email]}}
    expect(response).to have_http_status(:see_other)
    expect(SolidusMcp::Administration.role(candidate)).to eq(:admin)
    expect(SolidusMcp.configuration.superadmin_emails).to eq([superadmin.email.downcase])
  end

  it "cannot modify configured superadministrators through an assignment" do
    @actor = superadmin
    assign(user_id: superadmin.id)
    expect(response).to have_http_status(:forbidden)
    expect(SolidusMcp::Administrator.exists?(user: superadmin)).to be(false)
  end

  it "rejects missing CSRF and non-admin target accounts" do
    @actor = superadmin
    assign(csrf: "invalid")
    expect(response).to have_http_status(:unprocessable_entity)
    candidate.update!(admin: false)
    assign
    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to include("must be a Solidus administrator")
    expect(SolidusMcp::Administrator.exists?(user: candidate)).to be(false)
  end

  it "searches eligible accounts by email, excluding customers and privileged accounts" do
    @actor = superadmin
    candidate.update!(email: "joker@example.test")
    create_user(admin: false, mcp_admin: false).update!(email: "jokercustomer@example.test")
    create_user(superadmin: false).update!(email: "jokerassigned@example.test")
    get "#{path}/search", headers: headers, params: {query: "JOK"}
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(JSON.parse(response.body)).to eq("items" => [
      {"id" => candidate.id.to_s, "email" => candidate.email, "lock_version" => -1}
    ], "more" => false)
  end

  it "restricts account search to superadministrators" do
    [nil, create_user(mcp_admin: false), create_user(superadmin: false)].each do |actor|
      @actor = actor
      get "#{path}/search", headers: headers, params: {query: "user"}
      expect(response).to have_http_status(actor ? :forbidden : :unauthorized)
      expect(response.body).not_to include(candidate.email)
    end
  end

  it "bounds search results and treats wildcard characters literally" do
    @actor = superadmin
    25.times { create_user(mcp_admin: false) }
    get "#{path}/search", headers: headers
    result = JSON.parse(response.body)
    expect(result.fetch("items").size).to eq(20)
    expect(result.fetch("more")).to be(true)
    get "#{path}/search", headers: headers, params: {query: "%"}
    expect(JSON.parse(response.body).fetch("items")).to eq([])
    get "#{path}/search", headers: headers, params: {query: ["user"]}
    expect(response).to have_http_status(:bad_request)
    get "#{path}/search", headers: headers, params: {query: "x" * 101}
    expect(response).to have_http_status(:bad_request)
  end

  it "restores a searched account with its current assignment version" do
    @actor = superadmin
    assign
    assignment = SolidusMcp::Administrator.find_by!(user: candidate)
    update_assignment(assignment)
    get "#{path}/search", headers: headers, params: {query: candidate.email}
    version = JSON.parse(response.body).fetch("items").first.fetch("lock_version")
    expect(version).to eq(assignment.reload.lock_version)
    csrf = assign_csrf
    post path, headers: headers, params: {authenticity_token: csrf,
                                          administrator: {user_id: candidate.id, lock_version: version.to_s}}
    expect(response).to have_http_status(:see_other)
    expect(assignment.reload).to be_enabled
  end

  it "does not let a stale assignment form undo a newer role decision" do
    @actor = superadmin
    assign
    assignment = SolidusMcp::Administrator.find_by!(user: candidate)
    assignment.change!(actor: superadmin, enabled: false, lock_version: assignment.lock_version)
    update_assignment(assignment, enabled: "1", version: 0)
    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to include("Another superadministrator changed")
    expect(assignment.reload).not_to be_enabled
  end
end
