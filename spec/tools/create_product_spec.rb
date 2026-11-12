# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::CreateProduct do
  include_context "tool execution"
  after { SolidusMcp.configuration.default_shipping_category_id = nil }

  it "creates a product based on user input" do
    shipping = Spree::ShippingCategory.create!(name: "Default")
    expect {
      execute("create_product", name: "New Product", price: 100.50, shipping_category_id: shipping.id)
    }.to change { Spree::Product.count }.by(1)
    created_product = Spree::Product.last
    expect(created_product.name).to eq("New Product")
    expect(created_product.shipping_category_id).to eq(shipping.id)
    expect(created_product.price).to eq(BigDecimal("100.50"))
    expect(created_product.available_on).to be_nil
  end

  it "uses the configured shipping category when none is supplied" do
    shipping = Spree::ShippingCategory.create!(name: "Default")
    SolidusMcp.configure { |c| c.default_shipping_category_id = shipping.id }
    execute("create_product", name: "No Default Ship", price: 1.5)
    product = Spree::Product.last
    expect(product.shipping_category.id).to eq(shipping.id)
  end

  it "uses the supplied shipping category rather than the default" do
    default = Spree::ShippingCategory.create!(name: "Default")
    supplied = Spree::ShippingCategory.create!(name: "Supplied")
    SolidusMcp.configure { |c| c.default_shipping_category_id = default.id }
    execute("create_product", name: "Supplied Ship", price: 1.5, shipping_category_id: supplied.id)
    product = Spree::Product.last
    expect(product.shipping_category.id).to eq(supplied.id)
  end

  it "fails if no shipping category is supplied and no default category exists" do
    product_count = Spree::Product.count
    expect { execute("create_product", name: "No Shipping Category", price: 100) }.to raise_error(SolidusMcp::ToolError)
    expect(Spree::Product.count).to eq(product_count)
  end

  it "fails if an invalid shipping category is supplied" do
    default = Spree::ShippingCategory.create!(name: "Default")
    original_product_count = Spree::Product.count
    SolidusMcp.configure { |c| c.default_shipping_category_id = default.id }
    expect { execute("create_product", name: "Bad Shipping Category", price: 100, shipping_category_id: 12345) }.to raise_error(SolidusMcp::ToolError)
    expect(Spree::Product.count).to eql(original_product_count)
  end

  it "fails to create the product if the user does not have create_product permissions" do
    default = Spree::ShippingCategory.create!(name: "Default")
    original_product_count = Spree::Product.count
    SolidusMcp.configure { |c| c.default_shipping_category_id = default.id }
    @saved.change!(actor: user, permissions: ["search_products"], enabled: true, lock_version: @saved.lock_version)
    expect { execute("create_product", name: "No Auth", price: 100) }.to raise_error(SolidusMcp::AccessDenied)
    expect(Spree::Product.count).to eql(original_product_count)
  end

  it "returns a signature of {product_id: new_id, created: true} on a successful creation" do
    default = Spree::ShippingCategory.create!(name: "Default")
    SolidusMcp.configure { |c| c.default_shipping_category_id = default.id }
    result = execute("create_product", name: "Good Product", price: 100)
    new_product_id = Spree::Product.last.id
    expect(result[:product_id]).to eql(new_product_id)
    expect(result[:created]).to be(true)
  end

  it "rejects a whitespace-only name" do
    default = Spree::ShippingCategory.create!(name: "Default")
    original_product_count = Spree::Product.count
    SolidusMcp.configure { |c| c.default_shipping_category_id = default.id }
    expect { execute("create_product", name: " ", price: 100) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Spree::Product.count).to eql(original_product_count)
  end

  it "checks product attributes against Solidus creation permissions before saving" do
    shipping = Spree::ShippingCategory.create!(name: "Restricted")
    ability = Spree::Ability.new(user)
    ability.cannot :create, Spree::Product, shipping_category_id: shipping.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect(ability.can?(:create, Spree::Product)).to be(true)
    product_count = Spree::Product.count
    variant_count = Spree::Variant.count

    expect {
      execute("create_product", name: "Restricted product", price: 100, shipping_category_id: shipping.id)
    }.to raise_error(SolidusMcp::AccessDenied)

    expect(Spree::Product.count).to eq(product_count)
    expect(Spree::Variant.count).to eq(variant_count)
  end
end
