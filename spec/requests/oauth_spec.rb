# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Engine OAuth", type: :request do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:verifier) { "a" * 64 }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
  let(:request_params) do
    {client_id: application.uid, redirect_uri: application.redirect_uri, response_type: "code",
     scope: "mcp:read", state: "test-state", code_challenge: challenge, code_challenge_method: "S256",
     resource: SolidusMcp.configuration.endpoint_url}
  end

  def consent(params = request_params)
    get "/mcp/oauth/authorize", params: params, headers: {"X-Test-User" => user.id.to_s}
  end

  def authorize(params = request_params)
    consent(params)
    expect(response).to have_http_status(:ok)
    csrf = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')["value"]
    post "/mcp/oauth/authorize", params: params.merge(authenticity_token: csrf), headers: {"X-Test-User" => user.id.to_s}
    expect(response).to have_http_status(:found)
    Rack::Utils.parse_query(URI(response.location).query).fetch("code")
  end

  def exchange(code, **overrides)
    post "/mcp/oauth/token", params: {grant_type: "authorization_code", code: code,
                                      client_id: application.uid, redirect_uri: application.redirect_uri, code_verifier: verifier,
                                      resource: SolidusMcp.configuration.endpoint_url}.merge(overrides)
  end

  it "shows exactly the requested read and write consent sections" do
    consent
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Read access")
    expect(response.body).not_to include("<h2>Write access</h2>")
    expect(Nokogiri::HTML(response.body).at_css('input[value="mcp:write"]')["checked"]).to be_nil
    consent(request_params.merge(scope: "mcp:read mcp:write"))
    expect(response.body).to include("Read access", "Write access")
    consent(request_params.merge(scope: "mcp:write"))
    expect(response.body).to include("Write access")
    expect(response.body).not_to include("Read access")
  end

  it "issues audience-bound read-only tokens and preserves scopes during refresh" do
    code = authorize
    exchange(code)
    expect(response).to have_http_status(:ok)
    result = response.parsed_body
    expect(result["scope"]).to eq("mcp:read")
    token = Doorkeeper::AccessToken.by_token(result.fetch("access_token"))
    expect(token.resource).to eq(SolidusMcp.configuration.endpoint_url)
    expect(token.token).not_to eq(result["access_token"])
    post "/mcp/oauth/token", params: {grant_type: "refresh_token", client_id: application.uid,
                                      refresh_token: result.fetch("refresh_token"), resource: SolidusMcp.configuration.endpoint_url}
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["scope"]).to eq("mcp:read")
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
  end

  it "grants both scopes when the client requested and the user approved both" do
    code = authorize(request_params.merge(scope: "mcp:read mcp:write"))
    exchange(code)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["scope"].split).to contain_exactly("mcp:read", "mcp:write")
  end

  it "denies consent by a non-administrator even with a custom authentication hook" do
    user.update!(admin: false)
    consent
    expect(response).to have_http_status(:forbidden)
  end

  it "does not allow refresh to expand scopes" do
    code = authorize
    exchange(code)
    refresh = response.parsed_body.fetch("refresh_token")
    post "/mcp/oauth/token", params: {grant_type: "refresh_token", client_id: application.uid,
                                      refresh_token: refresh, resource: SolidusMcp.configuration.endpoint_url, scope: "mcp:read mcp:write"}
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_scope")
  end

  it "enforces PKCE and resource binding at exchange" do
    code = authorize
    exchange(code, resource: "https://other.example/mcp")
    expect(response.parsed_body["error"]).to eq("invalid_target")
    exchange(code, code_verifier: "b" * 64)
    expect(response.parsed_body["error"]).to eq("invalid_grant")
  end

  it "rejects unsupported scopes and malformed selections" do
    consent(request_params.merge(scope: "products:write"))
    expect(response).to have_http_status(:bad_request)
    ["mcp:write", [], ["unsupported"], [{scope: "mcp:write"}]].each do |selected|
      consent(request_params.merge(review_scopes: "1", requested_scopes: selected))
      expect(response.parsed_body["error"]).to eq("invalid_scope")
    end
  end

  it "does not exceed a client's registered scope ceiling" do
    application.update!(scopes: "mcp:read")
    consent(request_params.merge(scope: "mcp:read mcp:write"))
    expect(response.body).not_to include('value="Authorize"')
    expect(Doorkeeper::AccessGrant.count).to eq(0)
  end

  it "registers clients without issuing permissions or tokens" do
    post "/mcp/oauth/register", params: {client_name: "Example", redirect_uris: ["https://client.example/callback"], token_endpoint_auth_method: "none"}.to_json,
      headers: {"Content-Type" => "application/json"}
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["scope"]).to eq("mcp:read mcp:write")
    expect(Doorkeeper::AccessToken.count).to eq(0)
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
    post "/mcp/oauth/register", params: {redirect_uris: ["https://evil.example/*"]}.to_json, headers: {"Content-Type" => "application/json"}
    expect(response).to have_http_status(:bad_request)
  end
  it "reviews extra access and completes the original PKCE flow without granting tool permissions" do
    consent(request_params.except(:scope))
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[value="mcp:write"]')["checked"]).to be_nil
    form = document.at_css("#review-oauth-scopes")
    fields = form.css('input[type="hidden"]').to_h { |input| [input["name"], input["value"]] }
    fields["requested_scopes"] = %w[mcp:read mcp:write]
    consent(fields)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h2>Write access</h2>")
    expect(Doorkeeper::AccessGrant.count).to eq(0)
    expect(Doorkeeper::AccessToken.count).to eq(0)
    form = Nokogiri::HTML(response.body).at_css('form[method="post"]')
    approved = form.css("input[name]").to_h { |input| [input["name"], input["value"]] }
    %w[client_id redirect_uri state resource code_challenge code_challenge_method].each do |key|
      expect(approved[key]).to eq(request_params[key.to_sym])
    end
    post "/mcp/oauth/authorize", params: approved, headers: {"X-Test-User" => user.id.to_s}
    expect(response).to have_http_status(:found)
    callback = Rack::Utils.parse_query(URI(response.location).query)
    expect(callback["state"]).to eq("test-state")
    exchange(callback.fetch("code"))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["scope"].split).to contain_exactly("mcp:read", "mcp:write")
    expect(SolidusMcp::ConnectionPolicy.count).to eq(0)
  end

  it "enforces registration, callback, audience and PKCE limits during scope review" do
    application.update!(scopes: "mcp:read")
    consent
    expect(response.body).not_to include('value="mcp:write"')
    consent(request_params.merge(requested_scopes: %w[mcp:read mcp:write]))
    expect(response.body).not_to include('value="Authorize"')
    application.update!(scopes: "mcp:read mcp:write")
    [{redirect_uri: "https://evil.example/callback"}, {resource: "https://evil.example/mcp"}, {code_challenge_method: "plain"}].each do |invalid|
      consent(request_params.merge(requested_scopes: %w[mcp:read mcp:write]).merge(invalid))
      expect(response.body).not_to include('value="Authorize"')
    end
    expect(Doorkeeper::AccessGrant.count).to eq(0)
    expect(Doorkeeper::AccessToken.count).to eq(0)
  end

  it "requires review via GET and administrator consent before granting selected access" do
    consent
    csrf = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')["value"]
    post "/mcp/oauth/authorize", params: request_params.merge(authenticity_token: csrf, requested_scopes: %w[mcp:read mcp:write]),
      headers: {"X-Test-User" => user.id.to_s}
    expect(response).to have_http_status(:bad_request)
    user.update!(admin: false)
    consent(request_params.merge(requested_scopes: %w[mcp:read mcp:write]))
    expect(response).to have_http_status(:forbidden)
    expect(Doorkeeper::AccessGrant.count).to eq(0)
  end
end
