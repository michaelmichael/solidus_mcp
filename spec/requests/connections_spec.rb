# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP connection management", type: :request do
  let(:admin) { create_user }
  let(:application) { Doorkeeper::Application.create!(name: "Catalog assistant", redirect_uri: "https://client.example/callback", confidential: false) }
  let!(:token) { Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, scopes: "mcp:read mcp:write", expires_in: 3600, resource: SolidusMcp.configuration.endpoint_url) }
  let(:path) { "/admin/mcp_connections/#{application.id}?user_id=#{admin.id}" }
  let(:edit_path) { "/admin/mcp_connections/#{application.id}/edit?user_id=#{admin.id}" }

  before { skip "SolidusAdmin is optional" unless defined?(SolidusAdmin::Engine) }

  def request_headers
    {"X-Test-User" => @request_user&.id.to_s}
  end

  def form_token
    get edit_path, headers: request_headers
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css('form[action*="/mcp_connections/"] input[name="authenticity_token"]')["value"]
  end

  def save_policy(csrf: form_token, permissions: ["get_product"], enabled: "1", version: "-1")
    patch path, headers: request_headers, params: {authenticity_token: csrf,
                                                   connection_policy: {permissions: permissions, enabled: enabled, lock_version: version}}
  end

  it "requires browser authentication" do
    get "/admin/mcp_connections", headers: request_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "denies non-administrators" do
    @request_user = create_user(admin: false)
    get "/admin/mcp_connections", headers: request_headers
    expect(response).to have_http_status(:forbidden)
    get edit_path, headers: request_headers
    expect(response).to have_http_status(:forbidden)
  end

  it "renders connections and a resource permission matrix without exposing credentials" do
    @request_user = admin
    get "/admin/mcp_connections", headers: request_headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Catalog assistant", admin.email, "Edit permissions")
    get edit_path, headers: request_headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="update_product"', 'value="get_product"', "Products")
    expect(response.body).not_to include(token.token, token.plaintext_token)
  end

  it "shows missing scopes beside permissions without expanding tokens when saved" do
    token.update!(scopes: "mcp:read")
    @request_user = admin
    get edit_path, headers: request_headers
    expect(response.body).to include("Requires reconnection with mcp:write", "Reconnect to authorize additional access")
    save_policy(permissions: ["update_product"])
    expect(response).to have_http_status(:see_other)
    expect(flash[:notice]).to include("OAuth access is still missing")
    expect(token.reload.scopes.to_a).to eq(["mcp:read"])
    expect(Doorkeeper::AccessToken.count).to eq(1)
  end

  it "warns about mixed tokens instead of implying every client has the union of scopes" do
    token.update!(scopes: "mcp:read")
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, scopes: "mcp:write", resource: SolidusMcp.configuration.endpoint_url, expires_in: 3600)
    @request_user = admin
    get edit_path, headers: request_headers
    expect(response.body).to include("Some active tokens lack mcp:write")
    expect(response.body).to include("Some active tokens lack mcp:read")
  end

  it "ignores expired and revoked tokens when explaining missing scopes" do
    token.update!(scopes: "mcp:read")
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, scopes: "mcp:write", resource: SolidusMcp.configuration.endpoint_url, expires_in: 3600, created_at: 2.hours.ago)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, scopes: "mcp:write", resource: SolidusMcp.configuration.endpoint_url, expires_in: 3600, revoked_at: Time.current)
    @request_user = admin
    get edit_path, headers: request_headers
    expect(response.body).to include("Requires reconnection with mcp:write")
    expect(response.body).not_to include("Some active tokens lack")
  end

  it "explains expired connections and renders host instructions as text" do
    token.revoke
    @request_user = admin
    get edit_path, headers: request_headers
    expect(response.body).to include("No active access token")
    expect(response.body).not_to include("<script>unsafe")
  end

  it "respects Solidus restrictions on managing connections" do
    ability = Spree::Ability.new(admin)
    ability.cannot :manage, :mcp_connections
    allow(Spree::Ability).to receive(:new).with(admin).and_return(ability)
    @request_user = admin
    get edit_path, headers: request_headers
    expect(response).to have_http_status(:forbidden)
  end

  it "saves permissions with an actor-attributed audit" do
    @request_user = admin
    save_policy
    expect(response).to have_http_status(:see_other)
    policy = SolidusMcp::ConnectionPolicy.find_by!(application: application, user: admin)
    expect(policy.permissions).to eq(["get_product"])
    change = policy.policy_changes.last
    expect(change.actor_id).to eq(admin.id)
    expect(change.previous_values["permissions"]).to eq([])
    expect(change.new_values["permissions"]).to eq(["get_product"])
  end

  it "supports disabling a connection and denying all permissions" do
    @request_user = admin
    save_policy(permissions: [""], enabled: "0")
    expect(response).to have_http_status(:see_other)
    policy = SolidusMcp::ConnectionPolicy.find_by!(application: application, user: admin)
    expect(policy.permissions).to eq([])
    expect(policy).not_to be_enabled
  end

  it "rejects unregistered permissions" do
    @request_user = admin
    save_policy(permissions: ["users.promote", "products.destroy"])
    expect(response).to have_http_status(:unprocessable_entity)
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
    expect(SolidusMcp::PolicyChange.count).to eq(0)
  end

  it "requires CSRF protection for changes" do
    @request_user = admin
    save_policy(csrf: "invalid")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
  end

  it "does not overwrite a newer policy from a stale form" do
    policy = SolidusMcp::ConnectionPolicy.create!(application: application, user: admin, permissions: ["get_product"])
    @request_user = admin
    csrf = form_token
    policy.change!(actor: admin, permissions: [], enabled: false, lock_version: policy.lock_version)
    save_policy(csrf: csrf, version: "0")
    expect(response).to have_http_status(:conflict)
    expect(policy.reload.permissions).to eq([])
    expect(policy).not_to be_enabled
  end

  it "rolls back a permission edit if its audit fails" do
    policy = SolidusMcp::ConnectionPolicy.create!(application: application, user: admin, permissions: ["get_product"])
    allow_any_instance_of(SolidusMcp::PolicyChange).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(SolidusMcp::PolicyChange.new))
    expect { policy.change!(actor: admin, permissions: [], enabled: false, lock_version: 0) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(policy.reload.permissions).to eq(["get_product"])
    expect(policy).to be_enabled
  end

  it "does not let a default-policy form overwrite a newly saved restriction" do
    @request_user = admin
    csrf = form_token
    policy = SolidusMcp::ConnectionPolicy.create!(application: application, user: admin, permissions: [], enabled: false)
    save_policy(csrf: csrf, version: "-1")
    expect(response).to have_http_status(:conflict)
    expect(policy.reload.permissions).to eq([])
    expect(policy).not_to be_enabled
  end

  it "retains policy history when the OAuth client is removed" do
    policy = SolidusMcp::ConnectionPolicy.new(application: application, user: admin)
    policy.change!(actor: admin, permissions: [], enabled: false, lock_version: -1)
    uid = application.uid
    application.destroy!
    expect(policy.reload.application_uid).to eq(uid)
    expect(policy.policy_changes.last.actor_id).to eq(admin.id)
  end
end
