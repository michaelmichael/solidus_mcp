# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::SetVariantOptionValues do
  include_context "tool execution"

  let(:size) { create_option_type(name: "size", presentation: "Size") }
  let(:material) { create_option_type(name: "material", presentation: "Material") }
  let(:packs) { create_option_type(name: "packs", presentation: "Packs") }
  let(:small) { value(size, "1.5″") }
  let(:legacy) { value(size, "1.5″ (25-pack)") }
  let(:buna) { value(material, "Buna") }
  let(:pack25) { value(packs, "25-Pack") }
  let(:pack1) { value(packs, "1-Pack") }
  let(:variant) { Spree::Variant.create!(product: product, sku: "GASKET", price: "25", weight: 2, option_values: [legacy, buna]) }

  before { product.option_types = [size, material, packs] }

  def value(type, label)
    type.option_values.create!(name: label, presentation: label)
  end

  def replace(ids = [small.id, buna.id, pack25.id])
    execute("set_variant_option_values", variant_id: variant.id, option_value_ids: ids)
  end

  def restrict(&block)
    allow(Spree::Ability).to receive(:new).and_call_original
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end

  it "converts legacy pack sizing while preserving unrelated records and exposes readable assignments" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    variant
    original = variant.attributes.except("updated_at")
    prices = variant.prices.map(&:attributes)
    stock = variant.stock_items.map(&:attributes)
    image = variant.images.build(alt: "Gasket")
    image.attachment.attach(io: StringIO.new(Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")), filename: "gasket.png", content_type: "image/png")
    image.save!
    images = variant.images.pluck(:id)
    blob_id = image.attachment.blob.id
    store = Spree::Store.create!(name: "Test", url: "example.test", code: "test", mail_from_address: "store@example.test")
    order = Spree::Order.create!(store: store, currency: "USD")
    line = Spree::LineItem.create!(order: order, variant: variant, quantity: 1, price: "25")
    line_attributes = line.attributes
    result = replace
    expect(result).to include(variant_id: variant.id, product_id: product.id, changed: true)
    expect(result[:previous_option_values].map { |v| v[:option_value_presentation] }).to contain_exactly("1.5″ (25-pack)", "Buna")
    expect(result[:option_values].map { |v| [v[:option_type_presentation], v[:option_value_presentation]] }).to contain_exactly(["Size", "1.5″"], ["Material", "Buna"], ["Packs", "25-Pack"])
    expect(variant.reload.attributes.except("updated_at")).to eq(original)
    expect(variant.prices.map(&:attributes)).to eq(prices)
    expect(variant.stock_items.map(&:attributes)).to eq(stock)
    expect(variant.images.pluck(:id)).to eq(images)
    expect(image.reload.attachment.blob.id).to eq(blob_id)
    expect(line.reload.attributes).to eq(line_attributes)
    expect(location.stock_items.find_by!(variant_id: variant.id)).to be_present
    read = execute("get_product_variants", product_id: product.id)[:items].find { |v| v["id"] == variant.id }
    expect(read["option_values"]).to eq(result[:option_values])
  end

  it "adds 1-Pack to an existing individual variant after attaching Packs" do
    product.option_types = [size, material]
    variant.option_values = [small, buna]
    execute("add_product_option_type", product_id: product.id, option_type_id: packs.id)
    expect(replace([small.id, buna.id, pack1.id])[:changed]).to be(true)
    expect(variant.reload.option_values).to contain_exactly(small, buna, pack1)
  end

  it "returns unchanged for identical and reordered retries without saving" do
    replace
    timestamp = variant.reload.updated_at
    [[small.id, buna.id, pack25.id], [pack25.id, small.id, buna.id]].each do |ids|
      result = replace(ids)
      expect(result[:changed]).to be(false)
      expect(result[:previous_option_values]).to eq(result[:option_values])
    end
    expect(variant.reload.updated_at).to eq(timestamp)
  end

  it "rejects missing types, multiple values per type, duplicate IDs and unattached types atomically" do
    foreign = value(create_option_type(name: "other", presentation: "Other"), "Other")
    original = variant.option_value_ids.sort
    [[], [small.id, buna.id], [small.id, legacy.id, buna.id, pack25.id],
      [small.id, buna.id, pack25.id, pack25.id], [small.id, buna.id, foreign.id]].each do |ids|
      expect { replace(ids) }.to raise_error(SolidusMcp::ToolError)
      expect(variant.reload.option_value_ids.sort).to eq(original)
    end
  end

  it "rejects master variants" do
    expect { execute("set_variant_option_values", variant_id: product.master.id, option_value_ids: []) }.to raise_error(SolidusMcp::ToolError, /Master/)
  end

  it "rejects active duplicate combinations but permits deleted siblings" do
    sibling = Spree::Variant.create!(product: product, sku: "OTHER", price: 25, option_values: [small, buna, pack25])
    expect { replace }.to raise_error(SolidusMcp::ToolError, "Option combination is unavailable")
    expect(variant.reload.option_values).to contain_exactly(legacy, buna)
    sibling.update!(deleted_at: Time.current)
    expect(replace[:changed]).to be(true)
  end

  it "checks hidden sibling combinations without disclosing sibling details" do
    sibling = Spree::Variant.create!(product: product, sku: "HIDDEN", price: 25, option_values: [small, buna, pack25])
    restrict { |a| a.cannot :read, Spree::Variant, id: sibling.id }
    expect { replace }.to raise_error(SolidusMcp::ToolError, "Option combination is unavailable")
    expect(variant.reload.option_values).to contain_exactly(legacy, buna)
  end

  it "rejects deleted target variants and malformed inputs" do
    variant.update!(deleted_at: Time.current)
    expect { replace }.to raise_error(ActiveRecord::RecordNotFound)
    [nil, "1", [0], ["1"]].each do |ids|
      expect { replace(ids) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  it "rolls back association replacement when model validation fails" do
    original = variant.option_value_ids.sort
    allow_any_instance_of(Spree::Variant).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(variant))
    expect { replace }.to raise_error(ActiveRecord::RecordInvalid)
    expect(variant.reload.option_value_ids.sort).to eq(original)
  end

  it "requires its dedicated permission and write scope" do
    @saved.update!(permissions: ["update_variant"])
    expect { replace }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["set_variant_option_values"])
    token.update!(scopes: "mcp:read")
    expect { replace }.to raise_error(SolidusMcp::InsufficientScope)
  end

  it "rejects missing records" do
    expect { execute("set_variant_option_values", variant_id: 2_000_000_000, option_value_ids: []) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { replace([2_000_000_000]) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "scopes variants, products, values and types and preserves assignments" do
    variant
    [[Spree::Variant, :update, variant.id], [Spree::Product, :update, product.id],
      [Spree::OptionValue, :read, small.id], [Spree::OptionType, :read, packs.id]].each do |model, action, id|
      restrict { |a| a.cannot action, model, id: id }
      expect { replace }.to raise_error(ActiveRecord::RecordNotFound)
      expect(variant.reload.option_values).to contain_exactly(legacy, buna)
    end
  end

  it "rolls back when authorization rejects the resulting assignment" do
    variant
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Variant, option_values: {id: pack25.id}
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { replace }.to raise_error(SolidusMcp::AccessDenied)
    expect(variant.reload.option_values).to contain_exactly(legacy, buna)
  end

  it "rechecks grants after acquiring the product lock" do
    variant
    allow_any_instance_of(Spree::Product).to receive(:with_lock).and_wrap_original do |method, &block|
      method.call do
        @saved.update!(permissions: [])
        block.call
      end
    end
    expect { replace }.to raise_error(SolidusMcp::AccessDenied)
    expect(variant.reload.option_values).to contain_exactly(legacy, buna)
  end

  it "does not expose assigned labels outside read scope" do
    variant
    restrict { |a| a.cannot :read, Spree::OptionValue, id: legacy.id }
    expect { replace }.to raise_error(ActiveRecord::RecordNotFound)
    expect { execute("get_product_variants", product_id: product.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(variant.reload.option_values).to contain_exactly(legacy, buna)
  end

  it "honors option assignment attribute permissions" do
    restrict { |a| a.cannot :update, Spree::Variant, :option_value_ids }
    expect { replace }.to raise_error(SolidusMcp::AccessDenied)
    expect(variant.reload.option_values).to contain_exactly(legacy, buna)
  end
end
