# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::ConnectionScopes do
  let(:tool) { Struct.new(:scopes).new(%w[catalog:read products:write]) }

  it "does not combine partial grants from separate tokens" do
    status = described_class.new(["catalog:read", "products:write"])
    expect(status.warning(tool)).to include("Requires reconnection", "No active token has all scopes")
  end

  it "distinguishes mixed tokens from a connection with consistent scopes" do
    expect(described_class.new(["catalog:read products:write", "catalog:read"]).warning(tool)).to include("Some active tokens lack products:write")
    expect(described_class.new(["catalog:read products:write"]).warning(tool)).to be_nil
  end

  it "explains missing active tokens" do
    expect(described_class.new([]).warning(tool)).to include("No active access token", "catalog:read, products:write")
  end
end
