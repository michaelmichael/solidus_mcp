# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::UpdateVariant do
  include_context "tool execution"

  let(:variant) { Spree::Variant.create!(product: product, sku: "CHILD", price: "12.50") }

  def update_variant(changes = {sku: "UPDATED"})
    execute("update_variant", variant_id: variant.id, changes: changes)
  end

  def restrict(&block)
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end

  it "updates all supported attributes without changing prices, stock quantities, or ownership" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    item = location.stock_items.find_by!(variant_id: variant.id)
    prices = variant.prices.map(&:attributes)
    stock = item.attributes
    expect(update_variant(sku: "NEW-SKU", weight: "1.25", height: "2", width: "3.40",
      depth: "0", cost_price: "7.99", track_inventory: false)).to eq(variant_id: variant.id, updated: true)
    variant.reload
    expect(variant).to have_attributes(sku: "NEW-SKU", weight: BigDecimal("1.25"),
      height: BigDecimal(2), width: BigDecimal("3.4"), depth: BigDecimal(0),
      cost_price: BigDecimal("7.99"), track_inventory: false, product_id: product.id, is_master: false)
    expect(variant.prices.map(&:attributes)).to eq(prices)
    expect(item.reload.attributes).to eq(stock)
  end

  it "updates master variants without changing master status" do
    execute("update_variant", variant_id: product.master.id, changes: {sku: "MASTER"})
    expect(product.master.reload).to have_attributes(sku: "MASTER", is_master: true)
  end

  it "accepts string keys and preserves omitted attributes" do
    variant.update!(weight: 2, cost_price: 5, track_inventory: true)
    update_variant({"sku" => "STRING-KEY"})
    expect(variant.reload).to have_attributes(sku: "STRING-KEY", weight: BigDecimal(2), cost_price: BigDecimal(5), track_inventory: true)
  end

  it "does not interpret decimal strings using the store locale" do
    allow(I18n).to receive(:t).and_call_original
    allow(I18n).to receive(:t).with(:"number.currency.format.separator").and_return(",")
    update_variant(weight: "1.25", cost_price: "2.50")
    expect(variant.reload).to have_attributes(weight: BigDecimal("1.25"), cost_price: BigDecimal("2.50"))
  end

  it "accepts zero and storage limits without rounding" do
    update_variant(weight: "999999.99", height: "0", cost_price: "99999999.99")
    expect(variant.reload).to have_attributes(weight: BigDecimal("999999.99"), height: BigDecimal(0), cost_price: BigDecimal("99999999.99"))
    update_variant(cost_price: "0", track_inventory: true)
    expect(variant.reload).to have_attributes(cost_price: BigDecimal(0), track_inventory: true)
    expect { update_variant(weight: "1000000") }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "rejects prices, quantities, reassignment, master status, and other undeclared fields" do
    %i[price prices count_on_hand stock_items product_id is_master cost_currency option_value_ids].each do |key|
      expect { update_variant({key => 1}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    expect { execute("update_variant", variant_id: variant.id, changes: {sku: "X"}, unknown: true) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "rejects empty updates, invalid decimals, invalid booleans, and invalid IDs" do
    [{}, {sku: ""}, {track_inventory: "false"}, {cost_price: nil}].each do |changes|
      expect { update_variant(changes) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    %i[weight height width depth cost_price].each do |attribute|
      [1.25, "-1", "1.234", "NaN", "1e2", "1,25", "100000000"].each do |value|
        expect { update_variant({attribute => value}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
      end
    end
    expect { execute("update_variant", variant_id: 0, changes: {sku: "X"}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("update_variant", changes: {sku: "X"}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "preserves SKU uniqueness validations and rolls back the entire update" do
    original = variant.attributes
    expect { update_variant(sku: product.master.sku, weight: "5") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(variant.reload.attributes).to eq(original)
  end

  it "requires its dedicated grant and write scope" do
    @saved.update!(permissions: ["update_product", "update_variant_price"])
    expect { update_variant }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["update_variant"])
    token.update!(scopes: "mcp:read")
    expect { update_variant }.to raise_error(SolidusMcp::InsufficientScope)
    token.update!(scopes: "mcp:write")
    expect(update_variant[:updated]).to be(true)
  end

  it "rejects missing variants" do
    expect { execute("update_variant", variant_id: variant.id + 1, changes: {sku: "X"}) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "requires variant update ability even when the dedicated grant exists" do
    restrict { |ability| ability.cannot :update, Spree::Variant }
    expect { update_variant }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "rejects variants the user cannot update" do
    restrict { |ability| ability.cannot :update, Spree::Variant, id: variant.id }
    expect { update_variant }.to raise_error(ActiveRecord::RecordNotFound)
    expect(variant.reload.sku).to eq("CHILD")
  end

  it "rejects variants of products the user cannot update" do
    restrict { |ability| ability.cannot :update, Spree::Product, id: product.id }
    expect { update_variant }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "checks attribute permissions and rejects mixed updates atomically" do
    restrict { |ability| ability.cannot :update, Spree::Variant, :cost_price }
    expect { update_variant(sku: "DENIED", cost_price: "1") }.to raise_error(SolidusMcp::AccessDenied)
    expect(variant.reload.sku).to eq("CHILD")
    expect(update_variant(sku: "ALLOWED")[:updated]).to be(true)
  end

  it "checks record conditions after assignment" do
    restrict { |ability| ability.cannot :update, Spree::Variant, sku: "FORBIDDEN" }
    expect { update_variant(sku: "FORBIDDEN") }.to raise_error(SolidusMcp::AccessDenied)
    expect(variant.reload.sku).to eq("CHILD")
  end

  it "checks attribute conditions after assignment" do
    restrict { |ability| ability.cannot :update, Spree::Variant, :sku, sku: "FORBIDDEN" }
    expect { update_variant(sku: "FORBIDDEN") }.to raise_error(SolidusMcp::AccessDenied)
    expect(variant.reload.sku).to eq("CHILD")
  end

  it "rechecks grants after acquiring the variant lock" do
    variant
    allow_any_instance_of(Spree::Variant).to receive(:with_lock).and_wrap_original do |method, &block|
      method.call do
        @saved.update!(permissions: [])
        block.call
      end
    end
    expect { update_variant }.to raise_error(SolidusMcp::AccessDenied)
    expect(variant.reload.sku).to eq("CHILD")
  end
end
