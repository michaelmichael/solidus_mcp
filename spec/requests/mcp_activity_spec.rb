# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP activity browser", type: :request do
  let(:superadmin) { create_user }
  let(:path) { "/admin/mcp_activity" }
  before { skip "SolidusAdmin is optional" unless defined?(SolidusAdmin::Engine) }

  def headers(actor)
    {"X-Test-User" => actor&.id.to_s}
  end

  def event(actor, **overrides)
    SolidusMcp::ActivityEvent.create!({event_id: SecureRandom.uuid, user_id: actor.id,
                                       actor_role: SolidusMcp::Administration.role(actor).to_s, application_id: 1,
                                       application_name: "Test client", protocol_method: "tools/call", tool_name: "get_product",
                                       action: "read", status: "succeeded", started_at: Time.current, finished_at: Time.current, duration_ms: 5}.merge(overrides))
  end

  it "requires authentication and is read-only" do
    get path
    expect(response).to have_http_status(:unauthorized)
    get path, headers: headers(create_user(admin: false, mcp_admin: false))
    expect(response).to have_http_status(:forbidden)
    item = event(superadmin)
    delete "#{path}/#{item.id}", headers: headers(superadmin)
    expect(response).to have_http_status(:not_found)
    expect(SolidusMcp::ActivityEvent.exists?(item.id)).to be(true)
  end

  it "lets users see only their own activity, including when filtering someone else" do
    owner = create_user(mcp_admin: false)
    own = event(owner)
    hidden = event(superadmin)
    get path, headers: headers(owner)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.event_id)
    expect(response.body).not_to include(hidden.event_id)
    get path, headers: headers(owner), params: {user: superadmin.id}
    expect(response.body).not_to include(hidden.event_id, own.event_id)
  end

  it "respects administrator hierarchy and historical privileged activity" do
    manager = create_user(superadmin: false)
    ordinary = create_user(mcp_admin: false)
    manager_event = event(manager)
    ordinary_event = event(ordinary)
    super_event = event(superadmin)
    historic = event(ordinary, actor_role: "superadmin")
    get path, headers: headers(manager)
    expect(response.body).to include(manager_event.event_id, ordinary_event.event_id)
    expect(response.body).not_to include(super_event.event_id, historic.event_id)
    get path, headers: headers(superadmin)
    expect(response.body).to include(super_event.event_id, manager_event.event_id, ordinary_event.event_id, historic.event_id)
  end

  it "combines user, tool, type, outcome and time filters" do
    owner = create_user(mcp_admin: false)
    match = event(owner, action: "delete", tool_name: "remove_product_image", status: "denied", started_at: Time.utc(2026, 11, 12, 10))
    hidden = event(owner, action: "read", started_at: Time.utc(2026, 11, 11, 10))
    get path, headers: headers(superadmin), params: {user: owner.email, tool: "remove_product_image", action_type: "delete", outcome: "denied", from: "2026-11-12T09:00:00Z", to: "2026-11-12T11:00:00Z"}
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(match.event_id)
    expect(response.body).not_to include(hidden.event_id)
  end

  it "rejects invalid filters and impossible time ranges" do
    [{outcome: "unknown"}, {action_type: "execute"}, {from: "not-a-time"}, {from: "2026-02-31T10:00"},
      {from: "2026-11-13T10:00", to: "2026-11-12T10:00"}, {before_id: "bad"}].each do |filters|
      get path, headers: headers(superadmin), params: filters
      expect(response).to have_http_status(:bad_request)
    end
  end

  it "escapes client metadata and retains attribution for deleted user records" do
    actor = create_user(mcp_admin: false)
    item = event(actor, application_name: "<script>private()</script>")
    actor_id = actor.id
    actor.destroy!
    get path, headers: headers(superadmin)
    expect(response.body).to include(item.event_id, "User ##{actor_id}", "&lt;script&gt;")
    expect(response.body).not_to include("<script>private()")
  end

  it "paginates a bounded result set and keeps filter parameters" do
    51.times { event(superadmin, tool_name: "get_product") }
    get path, headers: headers(superadmin), params: {tool: "get_product"}
    document = Nokogiri::HTML(response.body)
    expect(document.css("tr[data-event-id]").size).to eq(50)
    older = document.css("a").find { |link| link.text == "Older" }
    expect(older["href"]).to include("tool=get_product", "before_id=")
    get older["href"], headers: headers(superadmin)
    expect(Nokogiri::HTML(response.body).css("tr[data-event-id]").size).to eq(1)
  end
end
