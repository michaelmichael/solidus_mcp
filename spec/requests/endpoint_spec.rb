# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Engine MCP endpoint", type: :request do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:bearer) { token.plaintext_token }

  def rpc(method, params = {}, authorization: "Bearer #{bearer}", extra_headers: {})
    post "/mcp", params: {jsonrpc: "2.0", id: 1, method: method, params: params}.to_json,
      headers: {"Authorization" => authorization, "Content-Type" => "application/json",
                "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-11-25"}.merge(extra_headers)
  end

  def payload
    body = response.body
    body = body.lines.find { |line| line.start_with?("data:") }.delete_prefix("data:").strip if body.start_with?("event:", "data:")
    JSON.parse(body)
  end

  it "provides resource and authorization metadata" do
    get "/mcp/metadata"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["resource"]).to eq(SolidusMcp.configuration.endpoint_url)
    get "/.well-known/oauth-authorization-server"
    expect(response.parsed_body["scopes_supported"]).to eq(%w[mcp:read mcp:write])
  end

  it "challenges absent credentials without accepting query tokens" do
    post "/mcp?access_token=not-a-bearer", params: "{}", headers: {"Content-Type" => "application/json"}
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("resource_metadata=")
  end

  it "discovers and executes tools through the engine-owned transport" do
    grant(application: application, user: user, permissions: ["get_product"])
    rpc("tools/list")
    expect(response).to have_http_status(:ok)
    expect(payload.dig("result", "tools").map { |tool| tool["name"] }).to eq(["get_product"])
    product = create_product
    rpc("tools/call", {name: "get_product", arguments: {product_id: product.id}})
    expect(payload.dig("result", "structuredContent", "id")).to eq(product.id)
  end

  it "returns standard step-up challenges only for enabled tools" do
    bearer
    token.update!(scopes: "mcp:read")
    saved = grant(application: application, user: user, permissions: ["update_product"])
    rpc("tools/call", {name: "update_product", arguments: {product_id: 1, changes: {name: "X"}}})
    expect(response).to have_http_status(:forbidden)
    expect(response.headers["WWW-Authenticate"]).to include('error="insufficient_scope"', 'scope="mcp:write"')
    saved.update!(permissions: [])
    rpc("tools/call", {name: "update_product", arguments: {product_id: 1, changes: {name: "X"}}})
    expect(response.headers["WWW-Authenticate"]).to be_nil
    expect(payload).to have_key("error")
  end

  it "bounds JSON request bodies before inspecting tool calls" do
    post "/mcp", params: " " * (1.megabyte + 1), headers: {"Authorization" => "Bearer #{bearer}", "Content-Type" => "application/json"}
    expect(response).to have_http_status(:payload_too_large)
  end

  it "rejects revoked tokens and disabled connections immediately" do
    bearer
    saved = grant(application: application, user: user)
    rpc("tools/list")
    expect(response).to have_http_status(:ok)
    saved.update!(enabled: false)
    rpc("tools/list")
    expect(response).to have_http_status(:forbidden)
    token.revoke
    rpc("tools/list")
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a token for another resource and untrusted origins" do
    bearer
    token.update!(resource: "https://other.example/mcp")
    rpc("tools/list")
    expect(response).to have_http_status(:unauthorized)
    token.update!(resource: SolidusMcp.configuration.endpoint_url)
    rpc("tools/list", {}, extra_headers: {"Origin" => "https://attacker.example"})
    expect(response).to have_http_status(:forbidden)
  end
end
