# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::OauthScopes do
  around do |example|
    original = SolidusMcp.scope_implications
    SolidusMcp.scope_implications = {
      "mcp:read" => %w[catalog:read sales:read],
      "mcp:write" => %w[mcp:read prices:write products:write inventory:write]
    }
    example.run
  ensure
    SolidusMcp.scope_implications = original
  end

  it "supports broad consent without promoting narrow or read-only grants" do
    expect(described_class.permits?(["mcp:write"], "catalog:read")).to be(true)
    expect(described_class.permits?(["mcp:write"], "prices:write")).to be(true)
    expect(described_class.permits?(["mcp:read"], "prices:write")).to be(false)
    expect(described_class.permits?(["prices:write"], "mcp:write")).to be(false)
    expect(described_class.permits?(["prices:write"], "inventory:write")).to be(false)
    expect(described_class.permits?([], "catalog:read")).to be(false)
  end

  it "uses the same implications for connection warnings without pooling tokens" do
    tool = Struct.new(:scopes).new(%w[catalog:read prices:write])
    expect(SolidusMcp::ConnectionScopes.new(["mcp:write"]).warning(tool)).to be_nil
    expect(SolidusMcp::ConnectionScopes.new(["mcp:read", "prices:write"]).warning(tool)).to include("Requires reconnection")
  end

  it "terminates cyclic configuration and retains exact grants by default" do
    SolidusMcp.scope_implications = {"a" => ["b"], "b" => ["a"]}
    expect(described_class.expand(["a"])).to eq(%w[a b])
    SolidusMcp.scope_implications = {}
    expect(described_class.expand(["mcp:write"])).to eq(["mcp:write"])
  end
end
