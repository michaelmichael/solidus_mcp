# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Policy do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { TestCatalog::Credential.new(token, user) }
  let(:policy) { described_class.new(credential) }
  let(:read_tool) { SolidusMcp.registry.tools.fetch("read_entry") }
  let(:publish_tool) { SolidusMcp.registry.tools.fetch("publish_entry") }

  it "denies an unconfigured connection by default" do
    expect(policy.allowed?(read_tool)).to be(false)
    expect { policy.authorize!(read_tool) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "rejects unregistered tool objects even with matching names" do
    grant(application: application, user: user)
    expect(policy.allowed?(TestCatalog.registry.tools.fetch("read_entry"))).to be(false)
  end

  it "separates read and named method grants" do
    grant(application: application, user: user, permissions: ["entries.read"])
    expect(policy.allowed?(read_tool)).to be(true)
    expect(policy.allowed?(publish_tool)).to be(false)
  end

  it "does not let a connection grant exceed OAuth scopes" do
    token.update!(scopes: "catalog:read")
    grant(application: application, user: user)
    expect(policy.allowed?(publish_tool)).to be(false)
  end

  it "denies revoked and expired credentials" do
    grant(application: application, user: user)
    token.revoke
    expect(policy.allowed?(read_tool)).to be(false)
    token.update!(revoked_at: nil, created_at: 2.hours.ago)
    expect(policy.allowed?(read_tool)).to be(false)
  end

  it "preserves grants across token rotation but isolates users and applications" do
    grant(application: application, user: user, permissions: ["entries.read"])
    rotated = create_token(application: application, user: user)
    expect(described_class.new(TestCatalog::Credential.new(rotated, user)).allowed?(read_tool)).to be(true)
    other_user = create_user
    other_token = create_token(application: application, user: other_user)
    expect(described_class.new(TestCatalog::Credential.new(other_token, other_user)).allowed?(read_tool)).to be(false)
    other_token = create_token(application: create_application, user: user)
    expect(described_class.new(TestCatalog::Credential.new(other_token, user)).allowed?(read_tool)).to be(false)
  end

  it "uses a saved empty policy instead of compatibility defaults" do
    SolidusMcp.default_permissions = ["entries.read"]
    expect(policy.allowed?(read_tool)).to be(true)
    grant(application: application, user: user, permissions: [])
    expect(policy.allowed?(read_tool)).to be(false)
  end

  it "applies policy edits to a reused policy instance" do
    saved = grant(application: application, user: user)
    expect(policy.allowed?(read_tool)).to be(true)
    saved.change!(actor: user, permissions: [], enabled: false, lock_version: 0)
    expect(policy.allowed?(read_tool)).to be(false)
  end

  it "intersects grants with the user's Solidus abilities" do
    user.update!(admin: false)
    grant(application: application, user: user)
    expect(policy.allowed?(publish_tool)).to be(false)
  end

  it "scopes collections and checks records using Solidus abilities" do
    visible = CatalogEntry.create!(name: "Visible")
    hidden = CatalogEntry.create!(name: "Hidden")
    ability = Spree::Ability.new(user)
    ability.cannot :read, CatalogEntry, id: hidden.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect(policy.scope(CatalogEntry)).to contain_exactly(visible)
    expect { policy.authorize_record!(:read, hidden) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "requires all permissions of a tool spanning resources" do
    registry = SolidusMcp::Registry.new
    registry.resource :entries, model: "CatalogEntry", label: "Entries", actions: {read: :read}
    registry.resource :users, model: "TestUser", label: "Users", actions: {read: :read}
    registry.tool :read_entry, resource: :entries, permissions: ["entries.read", "users.read"],
      handler: "TestCatalog::Operations", definition: {scope: "catalog:read", read_only: true, description: "Read with owner", properties: {}, required: []}
    SolidusMcp.registry = registry.seal!
    saved = grant(application: application, user: user, permissions: ["entries.read"])
    tool = registry.tools.fetch("read_entry")
    expect(policy.allowed?(tool)).to be(false)
    saved.update!(permissions: ["entries.read", "users.read"])
    expect(policy.allowed?(tool)).to be(true)
  end
end
