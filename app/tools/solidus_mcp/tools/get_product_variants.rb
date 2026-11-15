# frozen_string_literal: true

module SolidusMcp
  module Tools
    class GetProductVariants < Base
      tool_name :get_product_variants
      description "List authorized product variants, including the master variant, with IDs, SKUs, and assigned option type/value IDs and labels."
      category "Products"
      permission "get_product_variants"
      read_only true
      ability :read, "Spree::Product"
      ability :read, "Spree::Variant"
      input :product_id, type: "integer", minimum: 1, required: true
      pagination

      protected

      def call(product_id:, after_id: 0, limit: 25)
        policy.authorize_record!(:read, policy.scope(Spree::Product).find(product_id))
        page(variants.where(product_id: product_id), after_id: after_id, limit: limit) do |variant|
          serializers.variant(variant).merge("option_values" => serializers.option_assignment(variant.option_values))
        end
      end
    end
  end
end
