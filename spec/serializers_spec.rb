# frozen_string_literal: true

require "spec_helper"
require "alba"

RSpec.describe "Host serializers" do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:credential) { SolidusMcp::Credential.new(create_token(application: application, user: user), user) }
  let(:product) { create_product }
  let(:store) { Spree::Store.create!(name: "Test", url: "example.test", code: "test", mail_from_address: "store@example.test") }
  let(:order) { Spree::Order.create!(store: store, currency: "USD", email: "customer@example.test") }

  before { grant(application: application, user: user) }

  def execute(name, **arguments)
    SolidusMcp.registry.tools.fetch(name).class_name.constantize.execute(credential: credential, **arguments)
  end

  def configure_serializer(kind, &implementation)
    klass = Class.new
    klass.define_singleton_method(:call, &implementation)
    stub_const("HostSerializer", klass)
    SolidusMcp.configuration.public_send(:"#{kind}_serializer=", "HostSerializer")
    klass
  end

  it "keeps the default representations when no serializers are configured" do
    expect(execute("get_product", product_id: product.id)).to include("id" => product.id, "name" => product.name)
    expect(execute("get_order", order_id: order.id)).to include(id: order.id, currency: "USD", line_items: [])
  end

  it "uses a plain Ruby serializer for product details and search without changing pagination" do
    configure_serializer(:product) { |record, context:| {id: record.id, label: record.name.upcase}.freeze }
    expect(execute("get_product", product_id: product.id)).to eq(id: product.id, label: "TEST PRODUCT")
    create_product(sku: "SKU-2")
    result = execute("search_products", query: "Test", limit: 1)
    expect(result[:items]).to eq([{id: product.id, label: "TEST PRODUCT"}])
    expect(result[:next_after_id]).to eq(product.id)
    following = execute("search_products", query: "Test", after_id: result[:next_after_id], limit: 1)
    expect(following[:items].length).to eq(1)
    expect(following[:next_after_id]).to be_nil
  end

  it "accepts an Alba adapter returning a hash rather than encoded JSON" do
    resource = Class.new do
      include Alba::Resource
      attributes :id, :name
      attribute(:slug_length) { |record| record.slug.length }
    end
    stub_const("ProductResource", resource)
    configure_serializer(:product) { |record, context:| ProductResource.new(record).to_h }
    expect(execute("get_product", product_id: product.id).stringify_keys)
      .to eq("id" => product.id, "name" => product.name, "slug_length" => product.slug.length)
  end

  it "authorizes the primary record before calling host code" do
    klass = configure_serializer(:product) { |record, context:| {id: record.id} }
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::Product, id: product.id
    allow(Spree::Ability).to receive(:new).and_return(ability)
    expect(klass).not_to receive(:call)
    expect { execute("get_product", product_id: product.id) }.to raise_error(ActiveRecord::RecordNotFound)
    policy = SolidusMcp::Policy.new(credential)
    expect { SolidusMcp::Serializers.new(policy).product(product) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "does not bypass the tool grant when a serializer is configured" do
    klass = configure_serializer(:product) { |record, context:| {id: record.id} }
    SolidusMcp::ConnectionPolicy.find_by!(application: application, user: user).update!(permissions: [])
    expect(klass).not_to receive(:call)
    expect { execute("get_product", product_id: product.id) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "passes the policy context for authorization of related records" do
    related = create_product(sku: "RELATED")
    configure_serializer(:product) do |record, context:|
      context.authorize_record!(:read, related)
      {id: record.id, related_id: related.id}
    end
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::Product, id: related.id
    allow(Spree::Ability).to receive(:new).and_return(ability)
    expect { execute("get_product", product_id: product.id) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "omits optional related fields when access is denied and includes them when permitted" do
    related = create_product(sku: "RELATED")
    configure_serializer(:product) do |record, context:|
      result = {id: record.id}
      result[:related_name] = related.name if context.can?(:read, related)
      result
    end
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::Product, id: related.id
    allow(Spree::Ability).to receive(:new).and_return(ability)
    expect(execute("get_product", product_id: product.id)).to eq(id: product.id)

    ability.can :read, Spree::Product, id: related.id
    expect(execute("get_product", product_id: product.id)).to eq(id: product.id, related_name: related.name)
  end

  it "treats missing optional records as unavailable even for an administrator" do
    configure_serializer(:product) do |record, context:|
      result = {id: record.id}
      result[:related_name] = "Unexpected" if context.can?(:read, nil)
      result
    end
    expect(execute("get_product", product_id: product.id)).to eq(id: product.id)
  end

  it "customizes order search and detail fields while retaining tool-owned line items and status" do
    item = Spree::LineItem.create!(order: order, variant: product.master, quantity: 2, price: 12.5)
    configure_serializer(:order) { |record, context:| {reference: record.number}.freeze }
    expect(execute("get_order", order_id: order.id))
      .to eq(reference: order.number,
        line_items: [{id: item.id, variant_id: product.master.id, quantity: 2, price: "12.5"}], line_items_truncated: false)
    expect(execute("search_orders")[:items]).to eq([{reference: order.number}])
    expect(execute("get_order_status", order_id: order.id)).to include(id: order.id, state: order.state)
  end

  it "returns custom fields as structured MCP content" do
    configure_serializer(:product) { |record, context:| {id: record.id, custom_label: "Store product"} }
    server = SolidusMcp::Server.build(credential: credential)
    result = JSON.parse(server.handle_json({jsonrpc: "2.0", id: 1, method: "tools/call",
                                            params: {name: "get_product", arguments: {product_id: product.id}}}.to_json))
    expect(result.dig("result", "structuredContent")).to eq("id" => product.id, "custom_label" => "Store product")
  end

  it "rejects encoded JSON, arrays, invalid field names, and duplicate string/symbol keys" do
    ["{}", [], {1 => "invalid"}, {"id" => 2}.merge(id: 1)].each do |result|
      configure_serializer(:product) { |record, context:| result }
      expect { execute("get_product", product_id: product.id) }.to raise_error(SolidusMcp::ToolError)
    end
  end

  it "rejects replacement of the order tool's line items or truncation indicator" do
    [:line_items, "line_items", :line_items_truncated, "line_items_truncated"].each do |key|
      configure_serializer(:order) { |record, context:| {key => []} }
      expect { execute("get_order", order_id: order.id) }.to raise_error(SolidusMcp::ToolError, /cannot replace/)
    end
  end

  it "validates configuration during Rails prepare" do
    SolidusMcp.configuration.product_serializer = Class.new
    expect { Rails.application.reloader.prepare! }.to raise_error(ArgumentError, /class-name string/)
    stub_const("HostSerializer", Class.new)
    SolidusMcp.configuration.product_serializer = "HostSerializer"
    expect { Rails.application.reloader.prepare! }.to raise_error(ArgumentError, /must implement/)
  end

  it "uses the current configured class rather than retaining an old class object" do
    configure_serializer(:product) { |record, context:| {revision: 1} }
    serializers = SolidusMcp::Serializers.new(SolidusMcp::Policy.new(credential))
    expect(serializers.product(product)).to eq(revision: 1)
    configure_serializer(:product) { |record, context:| {revision: 2} }
    expect(serializers.product(product)).to eq(revision: 2)
  end
end
