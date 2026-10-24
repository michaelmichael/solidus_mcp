# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Server do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { SolidusMcp::Credential.new(token, user) }
  let(:server) { described_class.build(credential: credential) }
  let(:product) { create_product }

  def rpc(method, params = {})
    JSON.parse(server.handle_json({jsonrpc: "2.0", id: 1, method: method, params: params}.to_json))
  end

  it "discovers and executes built-ins without host handlers" do
    grant(application: application, user: user, permissions: ["get_product"])
    expect(rpc("tools/list").dig("result", "tools").map { |tool| tool["name"] }).to eq(["get_product"])
    expect(rpc("tools/call", name: "get_product", arguments: {product_id: product.id}).dig("result", "structuredContent", "id")).to eq(product.id)
  end

  it "rechecks permissions on cached server tools" do
    saved = grant(application: application, user: user)
    server
    saved.update!(permissions: [])
    result = rpc("tools/call", name: "update_product", arguments: {product_id: product.id, changes: {name: "Wrong"}})
    expect(result.dig("result", "isError")).to be(true)
    expect(product.reload.name).to eq("Test product")
  end

  it "rejects arbitrary fields and hides write tools from read-only tokens" do
    grant(application: application, user: user)
    result = rpc("tools/call", name: "update_product", arguments: {product_id: product.id, changes: {deleted_at: Time.current.iso8601}})
    expect(result.key?("error") || result.dig("result", "isError")).to be(true)
    token.update!(scopes: "mcp:read")
    other = described_class.build(credential: credential)
    names = JSON.parse(other.handle_json({jsonrpc: "2.0", id: 2, method: "tools/list"}.to_json)).dig("result", "tools").map { |tool| tool["name"] }
    expect(names).not_to include("update_product", "update_variant_price", "bulk_update_variant_prices")
  end
end
