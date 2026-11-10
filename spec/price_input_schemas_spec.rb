# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Price tool input schemas" do
  shared_examples "a required nullable country" do
    let(:schema) { SolidusMcp.registry.tools.fetch(tool_name).input_schema }
    let(:validator) { MCP::Tool::InputSchema.new(schema) }

    it "uses separate single-type branches for the nullable country" do
      expect(country_schema).not_to have_key(:type)
      expect(country_schema.fetch(:anyOf).map { |branch| branch.fetch(:type) }).to eq(%w[string null])
    end

    it "accepts a country code or explicit null" do
      ["CA", nil].each do |country|
        expect { validator.validate_arguments(arguments_for.call(country)) }.not_to raise_error
      end
    end

    it "rejects a non-string, non-null country" do
      expect { validator.validate_arguments(arguments_for.call(123)) }
        .to raise_error(MCP::Tool::InputSchema::ValidationError)
    end

    it "rejects an omitted country" do
      arguments = arguments_for.call(nil)
      country_container.call(arguments).delete(:country_iso)
      expect { validator.validate_arguments(arguments) }
        .to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  context "for update_variant_price" do
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

  context "for bulk_update_variant_prices" do
    let(:tool_name) { "bulk_update_variant_prices" }
    let(:country_schema) { schema.fetch(:properties).fetch("entries").fetch(:items).fetch(:properties).fetch(:country_iso) }
    let(:arguments_for) { ->(country) { {entries: [{sku: "SKU-1", currency: "USD", country_iso: country, amount: "19.95"}]} } }
    let(:country_container) { ->(arguments) { arguments.fetch(:entries).first } }

    include_examples "a required nullable country"
  end
end
