# frozen_string_literal: true

module SolidusMcp
  module Tools
    class UpdateVariantPrice < Base
      tool_name :update_variant_price
      description "Update one existing variant price in an explicit currency and country context. Decimal amounts are strings; country_iso null selects the general-country price."
      category "Pricing"
      permission "update_variant_price"
      read_only false
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      ability :update, "Spree::Price"
      input :variant_id, type: "integer", minimum: 1, required: true
      input :currency, type: "string", pattern: "^[A-Z]{3}$", required: true
      input :country_iso, type: ["string", "null"], pattern: "^[A-Z]{2}$", required: true
      input :amount, type: "string", required: true

      protected

      def call(variant_id:, currency:, country_iso:, amount:)
        PriceUpdate.new(policy).call(variant_id: variant_id, currency: currency,
          country_iso: country_iso, amount: amount) { authorize! }
      end
    end
  end
end
