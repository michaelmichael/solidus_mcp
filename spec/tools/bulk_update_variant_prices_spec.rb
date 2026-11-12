# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"
require_relative "../support/nullable_country_schema"

RSpec.describe SolidusMcp::Tools::BulkUpdateVariantPrices do
  include_context "tool execution"

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

  it "rejects duplicate bulk targets" do
    entry = {sku: product.master.sku, amount: "1", currency: "USD", country_iso: nil}
    expect(execute("bulk_update_variant_prices", entries: [entry, entry])[:results].map { |row| row[:success] }).to eq([false, false])
  end

  context "input schema" do
    let(:tool_name) { "bulk_update_variant_prices" }
    let(:country_schema) { schema.fetch(:properties).fetch("entries").fetch(:items).fetch(:properties).fetch(:country_iso) }
    let(:arguments_for) { ->(country) { {entries: [{sku: "SKU-1", currency: "USD", country_iso: country, amount: "19.95"}]} } }
    let(:country_container) { ->(arguments) { arguments.fetch(:entries).first } }

    include_examples "a required nullable country"
  end
end
