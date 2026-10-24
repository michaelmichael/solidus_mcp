# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Policy do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { SolidusMcp::Credential.new(token, user) }
  let(:policy) { described_class.new(credential) }
  let(:read_tool) { SolidusMcp.registry.tools.fetch("get_product") }
  let(:write_tool) { SolidusMcp.registry.tools.fetch("update_product") }

  it "denies missing and empty connection policies" do
    expect(policy.allowed?(read_tool)).to be(false)
    grant(application: application, user: user, permissions: [])
    expect(policy.allowed?(read_tool)).to be(false)
  end

  it "requires the exact tool permission even when a related tool is granted" do
    grant(application: application, user: user, permissions: ["get_product"])
    expect(policy.allowed?(read_tool)).to be(true)
    expect(policy.allowed?(SolidusMcp.registry.tools.fetch("search_products"))).to be(false)
  end

  it "keeps read and write scopes independent" do
    grant(application: application, user: user)
    token.update!(scopes: "mcp:read")
    expect(policy.allowed?(read_tool)).to be(true)
    expect { policy.authorize!(write_tool) }.to raise_error(SolidusMcp::InsufficientScope)
    token.update!(scopes: "mcp:write")
    expect(policy.allowed?(read_tool)).to be(false)
    expect(policy.allowed?(write_tool)).to be(true)
  end

  it "rechecks token revocation, expiry, audience and user status" do
    grant(application: application, user: user)
    expect(policy.allowed?(read_tool)).to be(true)
    token.revoke
    expect(policy.allowed?(read_tool)).to be(false)
    token.update!(revoked_at: nil, created_at: 2.hours.ago)
    expect(policy.allowed?(read_tool)).to be(false)
    token.update!(created_at: Time.current, resource: "https://other.example/mcp")
    expect(policy.allowed?(read_tool)).to be(false)
    token.update!(resource: SolidusMcp.configuration.endpoint_url)
    user.update!(admin: false)
    expect(policy.allowed?(read_tool)).to be(false)
  end

  it "checks current permissions even on a reused policy" do
    saved = grant(application: application, user: user)
    expect(policy.allowed?(read_tool)).to be(true)
    saved.change!(actor: user, permissions: [], enabled: false, lock_version: saved.lock_version)
    expect(policy.allowed?(read_tool)).to be(false)
  end

  it "keeps policies through refresh but isolates applications and users" do
    grant(application: application, user: user)
    rotated = create_token(application: application, user: user)
    expect(described_class.new(SolidusMcp::Credential.new(rotated, user)).allowed?(read_tool)).to be(true)
    other = create_application
    token.update!(application: other)
    expect(policy.allowed?(read_tool)).to be(false)
  end

  it "scopes collections and checks individual records" do
    product = create_product
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::Product, id: product.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect(policy.scope(Spree::Product)).not_to include(product)
    expect { policy.authorize_record!(:read, product) }.to raise_error(SolidusMcp::AccessDenied)
  end
end
