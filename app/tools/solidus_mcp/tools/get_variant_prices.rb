# frozen_string_literal: true

module SolidusMcp
  module Tools
    class GetVariantPrices < Base
      tool_name :get_variant_prices
      description "List exact price rows for a variant, including currency and country context."
      category "Pricing"
      permission "get_variant_prices"
      read_only true
      ability :read, "Spree::Product"
      ability :read, "Spree::Variant"
      ability :read, "Spree::Price"
      input :variant_id, type: "integer", minimum: 1, required: true
      pagination

      protected

      def call(variant_id:, after_id: 0, limit: 25)
        serializers.variant(variants.find(variant_id))
        page(policy.scope(Spree::Price).where(variant_id: variant_id), after_id: after_id, limit: limit) { |price| serializers.price(price) }
      end
    end
  end
end
