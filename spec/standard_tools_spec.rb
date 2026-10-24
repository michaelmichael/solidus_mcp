# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Standard Solidus tools" do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { SolidusMcp::Credential.new(token, user) }
  let(:product) { create_product }
  before { grant(application: application, user: user) }

  def execute(name, **arguments)
    SolidusMcp.registry.tools.fetch(name).class_name.constantize.execute(credential: credential, **arguments)
  end

  it "reads products, variants and prices from Solidus" do
    product
    expect(execute("search_products", query: "SKU-1")[:items].first["id"]).to eq(product.id)
    variant = execute("get_product_variants", product_id: product.id)[:items].first
    expect(variant["sku"]).to eq("SKU-1")
    expect(execute("get_variant_prices", variant_id: variant["id"])[:items].first[:amount]).to eq("12.5")
  end

  it "updates supported attributes and preserves Solidus validations" do
    execute("update_product", product_id: product.id, changes: {description: "New description"})
    expect(product.reload.description).to eq("New description")
    expect { execute("update_product", product_id: product.id, changes: {name: ""}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("update_product", product_id: product.id, changes: {price: 1}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("update_product", product_id: product.id, changes: {name: " "}) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(product.reload.name).to eq("Test product")
  end

  it "enforces record restrictions before changing a product" do
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Product, id: product.id
    allow(Spree::Ability).to receive(:new).and_return(ability)
    expect { execute("update_product", product_id: product.id, changes: {description: "Denied"}) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.reload.description).not_to eq("Denied")
  end

  it "updates one price only in the explicit currency and country context" do
    variant = product.master
    euro = variant.prices.create!(currency: "EUR", amount: 15)
    result = execute("update_variant_price", variant_id: variant.id, currency: "USD", country_iso: nil, amount: "19.95")
    expect(result[:amount]).to eq("19.95")
    expect(euro.reload.amount).to eq(15)
    expect { execute("update_variant_price", variant_id: variant.id, currency: "GBP", country_iso: nil, amount: "12") }.to raise_error(SolidusMcp::ToolError, /unavailable/)
    expect { execute("update_variant_price", variant_id: variant.id, currency: "USD", country_iso: nil, amount: "NaN") }.to raise_error(SolidusMcp::ToolError)
  end

  it "keeps country prices separate and enforces price record permissions" do
    country = Spree::Country.create!(name: "Canada", iso_name: "CANADA", iso: "CA", iso3: "CAN", numcode: 124)
    localized = product.master.prices.create!(currency: "USD", country_iso: country.iso, amount: 17)
    execute("update_variant_price", variant_id: product.master.id, currency: "USD", country_iso: "CA", amount: "25")
    expect(localized.reload.amount).to eq(25)
    expect(product.master.default_price.reload.amount).to eq(BigDecimal("12.50"))
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Price, id: localized.id
    allow(Spree::Ability).to receive(:new).and_return(ability)
    expect { execute("update_variant_price", variant_id: product.master.id, currency: "USD", country_iso: "CA", amount: "1") }.to raise_error(SolidusMcp::ToolError)
    expect(localized.reload.amount).to eq(25)
  end

  it "stops later bulk writes when authorization is revoked after an entry" do
    first = product.master.default_price
    second = create_product(sku: "SKU-2")
    allow_any_instance_of(Spree::Price).to receive(:save!).and_wrap_original do |method, *args|
      result = method.call(*args)
      token.revoke if method.receiver.id == first.id
      result
    end
    result = execute("bulk_update_variant_prices", entries: [
      {sku: "SKU-1", amount: "22", currency: "USD", country_iso: nil},
      {sku: "SKU-2", amount: "33", currency: "USD", country_iso: nil}
    ])
    expect(result[:results].map { |entry| entry[:success] }).to eq([true, false])
    expect(first.reload.amount).to eq(22)
    expect(second.master.default_price.reload.amount).to eq(BigDecimal("12.50"))
  end

  it "returns individual bulk successes and failures without losing successful writes" do
    product
    second = create_product(sku: "SKU-2")
    result = execute("bulk_update_variant_prices", entries: [
      {sku: "SKU-1", amount: "21.25", currency: "USD", country_iso: nil},
      {sku: "MISSING", amount: "2.00", currency: "USD", country_iso: nil},
      {sku: "SKU-2", amount: "-1", currency: "USD", country_iso: nil}
    ])
    expect(result[:results].map { |entry| entry[:success] }).to eq([true, false, false])
    expect(product.master.default_price.reload.amount).to eq(BigDecimal("21.25"))
    expect(second.master.default_price.reload.amount).to eq(BigDecimal("12.50"))
  end

  it "rejects duplicate bulk targets and ambiguous price contexts" do
    entry = {sku: product.master.sku, amount: "1", currency: "USD", country_iso: nil}
    expect(execute("bulk_update_variant_prices", entries: [entry, entry])[:results].map { |row| row[:success] }).to eq([false, false])
    product.master.prices.create!(currency: "USD", amount: 33)
    expect { execute("update_variant_price", variant_id: product.master.id, currency: "USD", country_iso: nil, amount: "2") }.to raise_error(SolidusMcp::ToolError, /ambiguous/)
  end

  it "reads stock and order statuses without enabling mutations" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    item = location.stock_items.find_or_create_by!(variant: product.master)
    expect(execute("get_inventory_levels", variant_id: product.master.id)[:items].map { |row| row[:id] }).to include(item.id)
    expect(execute("search_inventory", query: product.master.sku)[:items].map { |row| row[:id] }).to include(item.id)
    store = Spree::Store.create!(name: "Test", url: "example.test", code: "test", mail_from_address: "store@example.test")
    order = Spree::Order.create!(store: store, currency: "USD")
    expect(execute("get_order_status", order_id: order.id)[:state]).to eq("cart")
    expect(execute("get_order", order_id: order.id)[:number]).to eq(order.number)
    expect(execute("search_orders", number: order.number)[:items].map { |row| row[:id] }).to eq([order.id])
    expect(SolidusMcp.registry.tools).not_to have_key("set_stock")
  end
end
