# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP HTTP audit coverage", type: :request do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:bearer) { token.plaintext_token }

  def invoke(name, arguments = {})
    post "/mcp", params: {jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: name, arguments: arguments}}.to_json,
      headers: {"Authorization" => "Bearer #{bearer}", "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-11-25", "X-Request-ID" => "audit-test-request"}
  end

  it "records a successful HTTP tool call once with its request ID" do
    grant(application: application, user: user, permissions: ["get_product"])
    product = create_product
    expect { invoke("get_product", product_id: product.id) }.to change(SolidusMcp::ActivityEvent, :count).by(1)
    expect(SolidusMcp::ActivityEvent.last).to have_attributes(status: "succeeded", request_id: "audit-test-request", user_id: user.id)
  end

  it "records scope challenges before SDK dispatch" do
    grant(application: application, user: user, permissions: ["update_product"])
    bearer
    token.update!(scopes: "mcp:read")
    expect { invoke("update_product", product_id: 1, changes: {name: "Sensitive"}) }.to change(SolidusMcp::ActivityEvent, :count).by(1)
    expect(response).to have_http_status(:forbidden)
    event = SolidusMcp::ActivityEvent.last
    expect(event).to have_attributes(tool_name: "update_product", action: "update", status: "denied")
    expect(event.attributes.to_json).not_to include("Sensitive", bearer)
  end

  it "records disabled connections and revoked known credentials without executing" do
    saved = grant(application: application, user: user)
    bearer
    saved.update!(enabled: false)
    invoke("get_product", product_id: 1)
    expect(response).to have_http_status(:forbidden)
    expect(SolidusMcp::ActivityEvent.last.status).to eq("denied")
    token.revoke
    invoke("get_product", product_id: 1)
    expect(response).to have_http_status(:unauthorized)
    expect(SolidusMcp::ActivityEvent.last).to have_attributes(status: "denied", user_id: user.id)
  end
end
