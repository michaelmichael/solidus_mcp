# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Variant creation tools" do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { SolidusMcp::Credential.new(token, user) }
  let(:product) { create_product }
  let(:option_type) { Spree::OptionType.create!(name: "size", presentation: "Size") }
  let(:option_value) { option_type.option_values.create!(name: "small", presentation: "Small") }
  let!(:connection) { grant(application: application, user: user) }

  def execute(name, **arguments)
    SolidusMcp.registry.tools.fetch(name).class_name.constantize.execute(credential: credential, **arguments)
  end

  def create_variant(**attributes)
    execute("create_variant", product_id: product.id, sku: "NEW-SKU", **attributes)
  end

  def create_option_value(**attributes)
    execute("create_option_value", option_type_id: option_type.id, name: "large", presentation: "Large", **attributes)
  end

  it "registers both tools as built-in writes with separate permissions" do
    %w[create_variant create_option_value].each do |name|
      entry = SolidusMcp.registry.tools.fetch(name)
      expect(entry.read_only).to be(false)
      expect(entry.permissions).to eq([name])
      expect(entry.scopes).to eq(["mcp:write"])
    end
  end

  it "creates a non-master variant with existing options and supported attributes" do
    product.option_types << option_type
    result = create_variant(option_value_ids: [option_value.id], price: 14.25,
      track_inventory: false, weight: 2, height: 3, width: 4, depth: 5, cost_price: 6)
    variant = Spree::Variant.find(result[:variant_id])
    expect(result).to eq(variant_id: variant.id, product_id: product.id, sku: "NEW-SKU", created: true)
    expect(variant.is_master).to be(false)
    expect(variant.option_values).to contain_exactly(option_value)
    expect(variant.price).to eq(BigDecimal("14.25"))
    expect(variant.track_inventory).to be(false)
    expect([variant.weight, variant.height, variant.width, variant.depth, variant.cost_price]).to eq([2, 3, 4, 5, 6])
  end

  it "defaults to the master price and follows stock item callbacks" do
    location = Spree::StockLocation.create!(name: "Warehouse", propagate_all_variants: true)
    variant = Spree::Variant.find(create_variant[:variant_id])
    expect(variant.price).to eq(product.master.price)
    expect(variant.stock_items.pluck(:stock_location_id)).to include(location.id)
  end

  it "creates an option value usable by a new variant without attaching option types" do
    result = create_option_value
    value = Spree::OptionValue.find(result[:option_value_id])
    expect(result).to eq(option_value_id: value.id, option_type_id: option_type.id,
      name: "large", presentation: "Large", created: true)
    expect(product.option_types).to be_empty
    product.option_types << option_type
    variant = Spree::Variant.find(create_variant(option_value_ids: [value.id])[:variant_id])
    expect(variant.option_values).to contain_exactly(value)
  end

  it "rejects unavailable option values without creating a variant" do
    expect { create_variant(option_value_ids: [0x7fffffff]) }
      .to raise_error(SolidusMcp::ToolError, /unavailable/)
    expect(product.variants.count).to eq(0)
  end

  it "rejects option values from types not attached to the product" do
    expect { create_variant(option_value_ids: [option_value.id]) }
      .to raise_error(SolidusMcp::ToolError, /product's option types/)
    expect(product.variants.count).to eq(0)
  end

  it "rejects multiple values of the same option type" do
    product.option_types << option_type
    second = option_type.option_values.create!(name: "medium", presentation: "Medium")
    expect { create_variant(option_value_ids: [option_value.id, second.id]) }
      .to raise_error(SolidusMcp::ToolError, /at most one/)
    expect(product.variants.count).to eq(0)
  end

  it "rejects duplicate option IDs, negative prices, and unsupported attributes" do
    [{option_value_ids: [1, 1]}, {price: -1}, {is_master: true}, {sku: ""}].each do |attributes|
      expect { create_variant(**attributes) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    expect(product.variants.count).to eq(0)
  end

  it "preserves Solidus validation for blank values and duplicate option names" do
    option_value
    expect { create_option_value(name: option_value.name) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create_option_value(presentation: " ") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(option_type.option_values.count).to eq(1)
    expect(product.variants.count).to eq(0)
  end

  it "rejects missing parents" do
    expect { execute("create_variant", product_id: 0x7fffffff, sku: "NEW") }.to raise_error(ActiveRecord::RecordNotFound)
    expect { execute("create_option_value", option_type_id: 0x7fffffff, name: "new", presentation: "New") }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it "requires each tool's connection permission and write consent" do
    %w[create_variant create_option_value].each do |name|
      connection.update!(permissions: SolidusMcp.registry.permissions - [name])
      expect { send(name) }.to raise_error(SolidusMcp::AccessDenied)
      connection.update!(permissions: SolidusMcp.registry.permissions)
      token.update!(scopes: "mcp:read")
      expect { send(name) }.to raise_error(SolidusMcp::InsufficientScope)
      token.update!(scopes: "mcp:read mcp:write")
    end
  end

  it "enforces parent record restrictions" do
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Product, id: product.id
    ability.cannot :update, Spree::OptionType, id: option_type.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { create_variant }.to raise_error(ActiveRecord::RecordNotFound)
    expect { create_option_value }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "enforces option value visibility" do
    product.option_types << option_type
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::OptionValue, id: option_value.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { create_variant(option_value_ids: [option_value.id]) }.to raise_error(SolidusMcp::ToolError, /unavailable/)
    expect(product.variants.count).to eq(0)
  end

  it "checks attributes against creation permissions before saving" do
    ability = Spree::Ability.new(user)
    ability.cannot :create, Spree::Variant, sku: "NEW-SKU"
    ability.cannot :create, Spree::OptionValue, name: "large"
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { create_variant }.to raise_error(SolidusMcp::AccessDenied)
    expect { create_option_value }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.variants.count).to eq(0)
    expect(option_type.option_values.count).to eq(0)
  end
end
