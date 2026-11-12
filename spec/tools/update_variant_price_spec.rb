# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"
require_relative "../support/nullable_country_schema"

RSpec.describe SolidusMcp::Tools::UpdateVariantPrice do
  include_context "tool execution"

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

  it "rejects ambiguous price contexts" do
    product.master.prices.create!(currency: "USD", amount: 33)
    expect { execute("update_variant_price", variant_id: product.master.id, currency: "USD", country_iso: nil, amount: "2") }.to raise_error(SolidusMcp::ToolError, /ambiguous/)
  end

  context "input schema" do
    let(:tool_name) { "update_variant_price" }
    let(:country_schema) { schema.fetch(:properties).fetch("country_iso") }
    let(:arguments_for) { ->(country) { {variant_id: 1, currency: "USD", country_iso: country, amount: "19.95"} } }
    let(:country_container) { ->(arguments) { arguments } }

    include_examples "a required nullable country"

    it "preserves the two-uppercase-letter country constraint" do
      ["ca", "CAN", ""].each do |country|
        expect { validator.validate_arguments(arguments_for.call(country)) }
          .to raise_error(MCP::Tool::InputSchema::ValidationError)
      end
    end
  end
end
