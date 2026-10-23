# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Registry do
  let(:registry) { described_class.new }
  let(:definition) { {scope: "catalog:read", description: "Read a product", properties: {id: {type: "integer"}}, required: ["id"], read_only: true} }

  before { registry.resource(:products, model: "Spree::Product", label: "Products", actions: {read: :read}) }

  it "rejects duplicate resources and tools" do
    expect { registry.resource(:products, model: "Spree::Product", label: "Products", actions: {read: :read}) }.to raise_error(ArgumentError, /Duplicate resource/)
    registry.tool(:read_product, resource: :products, permissions: ["products.read"], definition: definition, handler: "Example::Operations")
    expect { registry.tool(:read_product, resource: :products, permissions: ["products.read"], definition: definition, handler: "Example::Operations") }.to raise_error(ArgumentError, /Duplicate tool/)
  end

  it "fails closed for tools with missing or unknown permissions" do
    expect { registry.tool(:read_product, resource: :products, permissions: [], definition: definition, handler: "Example::Operations") }.to raise_error(ArgumentError, /needs permissions/)
    expect { registry.tool(:read_product, resource: :products, permissions: ["products.destroy"], definition: definition, handler: "Example::Operations") }.to raise_error(ArgumentError, /Unknown permission/)
  end

  it "seals the registry and its input schemas" do
    registry.tool(:read_product, resource: :products, permissions: ["products.read"], definition: definition, handler: "Example::Operations")
    registry.seal!
    expect { registry.tools.delete("read_product") }.to raise_error(FrozenError)
    expect { registry.tools["read_product"].input_schema[:properties][:id][:type].replace("string") }.to raise_error(FrozenError)
    expect(definition[:properties][:id][:type]).to eq("integer")
  end

  it "does not automatically grant a newly registered permission" do
    registry.resource(:orders, model: "Spree::Order", label: "Orders", actions: {cancel: :update})
    registry.tool(:cancel_order, resource: :orders, permissions: ["orders.cancel"], definition: definition, handler: "Example::Operations")
    admin = create_user
    application = Doorkeeper::Application.create!(name: "Test", redirect_uri: "https://client.example/callback")
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, scopes: "catalog:read", expires_in: 3600)
    policy = SolidusMcp::Policy.new(TestCatalog::Credential.new(token, admin), registry: registry)
    expect(policy.allowed?(registry.tools["cancel_order"])).to eq(false)
  end
end
