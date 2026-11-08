# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP connection management", type: :request do
  let(:admin) { create_user }
  let(:application) { Doorkeeper::Application.create!(name: "Catalog assistant", redirect_uri: "https://client.example/callback", confidential: false) }
  let!(:token) { Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, scopes: "mcp:read mcp:write", expires_in: 3600, resource: SolidusMcp.configuration.endpoint_url) }
  let(:path) { "/admin/mcp_connections/#{application.id}/owners/#{admin.id}" }
  let(:edit_path) { "/admin/mcp_connections/#{application.id}/owners/#{admin.id}/edit" }

  before { skip "SolidusAdmin is optional" unless defined?(SolidusAdmin::Engine) }

  def request_headers
    {"X-Test-User" => @request_user&.id.to_s}
  end

  def form_token(method = "patch", edit: edit_path)
    get edit, headers: request_headers
    expect(response).to have_http_status(:ok)
    form = Nokogiri::HTML(response.body).css('form[action*="/mcp_connections/"]').find do |element|
      element.at_css('input[name="_method"]')&.[]("value") == method
    end
    form.at_css('input[name="authenticity_token"]')["value"]
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

  it "redirects existing query-string edit links to a path containing the connection owner" do
    @request_user = admin
    get "/admin/mcp_connections/#{application.id}/edit", params: {user_id: admin.id}, headers: request_headers
    expect(response).to redirect_to(edit_path)
    follow_redirect!(headers: request_headers)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin.email)
  end

  it "redirects the earlier users path to avoid the Users sidebar matcher" do
    @request_user = admin
    get "/admin/mcp_connections/#{application.id}/users/#{admin.id}/edit", headers: request_headers
    expect(response).to redirect_to(edit_path)
  end

  it "preserves the selected connection owner when changing the admin theme" do
    @request_user = admin
    owner = create_user
    create_token(application: application, user: owner)
    owner_path = "/admin/mcp_connections/#{application.id}/owners/#{owner.id}/edit"
    get owner_path, params: {switch_to_theme: "solidus_dimmed", system_theme: "light"}, headers: request_headers
    expect(response).to redirect_to("#{owner_path}?account_menu_open=true")
    follow_redirect!(headers: request_headers)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(owner.email)
    expect(response.body).not_to include(admin.email)
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
  end

  it "marks connection edit pages as active in the AI connections navigation" do
    item = SolidusAdmin::Config.menu_items.find { |entry| entry[:key] == :mcp_connections }
    matcher = item.fetch(:match_path)
    expect(matcher.call(edit_path)).to be(true)
    expect(matcher.call("/admin/mcp_connections?deleted=1")).to be(true)
    expect(matcher.call("/admin/users")).to be(false)
    expect(matcher.call("/admin/mcp_connections_other")).to be(false)
    expect(edit_path).not_to match(%r{/(users|store_credits)})
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
  def delete_policy(version:, csrf: form_token("delete"))
    delete path, headers: request_headers, params: {authenticity_token: csrf, connection_policy: {lock_version: version.to_s}}
  end

  it "deletes a permission set, denies cached tools and retains its audit history" do
    @request_user = admin
    saved = grant(application: application, user: admin, permissions: ["get_product"])
    credential = SolidusMcp::Credential.new(token, admin)
    server = SolidusMcp::Server.build(credential: credential)
    delete_policy(version: saved.lock_version)
    expect(response).to have_http_status(:see_other)
    expect(saved.reload.deleted_at).to be_present
    expect(saved.permissions).to eq([])
    expect(saved).not_to be_enabled
    expect(saved.policy_changes.last.actor_id).to eq(admin.id)
    expect(saved.policy_changes.last.new_values["deleted_at"]).to be_present
    result = JSON.parse(server.handle_json({jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: "get_product", arguments: {product_id: 1}}}.to_json))
    expect(result.dig("result", "isError")).to be(true)
    expect(token.reload).not_to be_revoked
    get "/admin/mcp_connections", headers: request_headers
    expect(response.body).not_to include("Catalog assistant")
    get "/admin/mcp_connections?deleted=1", headers: request_headers
    expect(response.body).to include("Catalog assistant", "Review or restore")
  end

  it "can delete a connection with no saved permissions and restore it explicitly" do
    @request_user = admin
    delete_policy(version: -1)
    expect(response).to have_http_status(:see_other)
    saved = SolidusMcp::ConnectionPolicy.find_by!(application: application, user: admin)
    get edit_path, headers: request_headers
    expect(response.body).to include("Restore permission set")
    save_policy(version: saved.lock_version.to_s)
    expect(response).to have_http_status(:see_other)
    expect(saved.reload.deleted_at).to be_nil
    expect(saved.permissions).to eq(["get_product"])
    expect(saved).to be_enabled
    expect(saved.policy_changes.count).to eq(2)
  end

  it "does not delete a permission set from a stale form" do
    @request_user = admin
    saved = grant(application: application, user: admin, permissions: ["get_product"])
    csrf = form_token("delete")
    saved.change!(actor: admin, permissions: ["search_products"], enabled: true, lock_version: saved.lock_version)
    delete_policy(version: 0, csrf: csrf)
    expect(response).to have_http_status(:conflict)
    expect(saved.reload.deleted_at).to be_nil
    expect(saved.permissions).to eq(["search_products"])
  end

  it "requires CSRF and administrator authorization to delete" do
    @request_user = admin
    delete_policy(version: -1, csrf: "invalid")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
    csrf = form_token("delete")
    @request_user = create_user(admin: false)
    delete_policy(version: -1, csrf: csrf)
    expect(response).to have_http_status(:forbidden)
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
  end

  it "rolls back deletion when the audit fails and leaves other users untouched" do
    saved = grant(application: application, user: admin, permissions: ["get_product"])
    other_user = create_user
    other = grant(application: application, user: other_user, permissions: ["search_products"])
    allow_any_instance_of(SolidusMcp::PolicyChange).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(SolidusMcp::PolicyChange.new))
    expect { saved.delete_permissions!(actor: admin, lock_version: saved.lock_version) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(saved.reload.deleted_at).to be_nil
    expect(saved.permissions).to eq(["get_product"])
    expect(other.reload.permissions).to eq(["search_products"])
  end
  it "lets an MCP administrator manage another person's connection with an attributed audit" do
    owner = create_user(mcp_admin: false)
    create_token(application: application, user: owner)
    owner_path = "/admin/mcp_connections/#{application.id}/owners/#{owner.id}"
    @request_user = admin
    csrf = form_token(edit: "#{owner_path}/edit")
    patch owner_path, headers: request_headers, params: {authenticity_token: csrf,
                                                         connection_policy: {permissions: ["get_product"], enabled: "1", lock_version: "-1"}}
    expect(response).to have_http_status(:see_other)
    saved = SolidusMcp::ConnectionPolicy.find_by!(application: application, user: owner)
    expect(saved.permissions).to eq(["get_product"])
    expect(saved.policy_changes.last.actor_id).to eq(admin.id)
  end

  it "returns forbidden if MCP administration access changes before the management write" do
    @request_user = admin
    csrf = form_token
    allow(SolidusMcp::Administration).to receive(:can_manage?).and_return(true, false)
    save_policy(csrf: csrf)
    expect(response).to have_http_status(:forbidden)
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
  end

  context "as an assigned MCP administrator" do
    let(:manager) { create_user(superadmin: false) }
    let(:ordinary_user) { create_user(mcp_admin: false) }
    let(:peer) { create_user(superadmin: false) }
    let!(:manager_token) { create_token(application: application, user: manager) }
    let!(:ordinary_token) { create_token(application: application, user: ordinary_user) }
    let!(:peer_token) { create_token(application: application, user: peer) }
    let(:ordinary_path) { "/admin/mcp_connections/#{application.id}/owners/#{ordinary_user.id}" }

    before { @request_user = manager }

    it "shows ordinary users and its own read-only connection, but hides privileged peers" do
      get "/admin/mcp_connections", headers: request_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(manager.email, ordinary_user.email)
      expect(response.body).not_to include(admin.email, peer.email, "Manage MCP administrators")
    end

    it "can change ordinary users' permissions with an attributed audit" do
      csrf = form_token(edit: "#{ordinary_path}/edit")
      patch ordinary_path, headers: request_headers, params: {authenticity_token: csrf,
                                                              connection_policy: {permissions: ["get_product"], enabled: "1", lock_version: "-1"}}
      expect(response).to have_http_status(:see_other)
      saved = SolidusMcp::ConnectionPolicy.find_by!(application: application, user: ordinary_user)
      expect(saved.policy_changes.last.actor_id).to eq(manager.id)
    end

    it "cannot view or manage another administrator or a superadministrator" do
      [admin, peer].each do |owner|
        get "/admin/mcp_connections/#{application.id}/owners/#{owner.id}/edit", headers: request_headers
        expect(response).to have_http_status(:not_found)
      end
    end

    it "cannot change its own grants even with a valid CSRF token" do
      own_path = "/admin/mcp_connections/#{application.id}/owners/#{manager.id}"
      @request_user = admin
      csrf = form_token(edit: "#{own_path}/edit")
      @request_user = manager
      patch own_path, headers: request_headers, params: {authenticity_token: csrf,
                                                         connection_policy: {permissions: ["update_product"], enabled: "1", lock_version: "-1"}}
      expect(response).to have_http_status(:forbidden)
      expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
      get "#{own_path}/edit", headers: request_headers
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css("form")).to be_empty
    end
  end

  context "as an MCP user" do
    let(:mcp_user) { create_user(mcp_admin: false) }
    let!(:own_token) { create_token(application: application, user: mcp_user) }
    let(:own_path) { "/admin/mcp_connections/#{application.id}/owners/#{mcp_user.id}" }

    before { @request_user = mcp_user }

    it "lists only the person's own active connections" do
      get "/admin/mcp_connections", headers: request_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mcp_user.email, "View permissions")
      expect(response.body).not_to include(admin.email, "Edit permissions")
    end

    it "shows assigned permissions without any permission-management forms" do
      grant(application: application, user: mcp_user, permissions: ["get_product"])
      get "#{own_path}/edit", headers: request_headers
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.css("input[data-permission][checked]").map { |input| input["value"] }).to eq(["get_product"])
      expect(page.css("input[data-permission]:not([disabled])")).to be_empty
      expect(page.css("form, [data-select-all], [data-select-group]")).to be_empty
    end

    it "cannot view another person's connection through either route format" do
      get edit_path, headers: request_headers
      expect(response).to have_http_status(:not_found)
      get "/admin/mcp_connections/#{application.id}/edit", params: {user_id: admin.id}, headers: request_headers
      expect(response).to have_http_status(:not_found)
    end

    it "cannot forge permission edits or delete requests with a valid CSRF token" do
      saved = grant(application: application, user: mcp_user, permissions: ["get_product"])
      @request_user = admin
      csrf = form_token(edit: "#{own_path}/edit")
      delete_csrf = form_token("delete", edit: "#{own_path}/edit")
      @request_user = mcp_user
      patch own_path, headers: request_headers, params: {authenticity_token: csrf,
                                                         connection_policy: {permissions: ["update_product"], enabled: "1", lock_version: saved.lock_version}}
      expect(response).to have_http_status(:forbidden)
      delete own_path, headers: request_headers, params: {authenticity_token: delete_csrf,
                                                          connection_policy: {lock_version: saved.lock_version}}
      expect(response).to have_http_status(:forbidden)
      expect(saved.reload.permissions).to eq(["get_product"])
      expect(saved.deleted_at).to be_nil
      expect(saved.policy_changes.count).to eq(0)
    end

    it "lists only their own deleted connections and cannot restore them" do
      saved = grant(application: application, user: mcp_user, permissions: ["get_product"])
      other = grant(application: application, user: admin, permissions: ["get_product"])
      saved.delete_permissions!(actor: admin, lock_version: saved.lock_version)
      other.delete_permissions!(actor: admin, lock_version: other.lock_version)
      get "/admin/mcp_connections?deleted=1", headers: request_headers
      expect(response.body).to include(mcp_user.email)
      expect(response.body).not_to include(admin.email, "Review or restore")
      get "#{own_path}/edit", headers: request_headers
      expect(response.body).to include("Ask an MCP administrator to restore it")
      expect(Nokogiri::HTML(response.body).css("form")).to be_empty
    end

    it "removes management access on the next request after the role is revoked" do
      @request_user = admin
      csrf = form_token
      SolidusMcp.configuration.superadmin_emails.delete(admin.email.downcase)
      patch path, headers: request_headers, params: {authenticity_token: csrf,
                                                     connection_policy: {permissions: ["get_product"], enabled: "1", lock_version: "-1"}}
      expect(response).to have_http_status(:forbidden)
      expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
    end
  end
end
