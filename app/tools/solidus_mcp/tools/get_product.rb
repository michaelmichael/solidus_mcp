# frozen_string_literal: true

module SolidusMcp
  module Tools
    class GetProduct < Base
      tool_name :get_product
      description "Retrieve product descriptions and supported product attributes by ID."
      category "Products"
      permission "get_product"
      read_only true
      ability :read, "Spree::Product"
      input :product_id, type: "integer", minimum: 1, required: true

      protected

      def call(product_id:)
        serializers.product(policy.scope(Spree::Product).find(product_id))
      end
    end
  end
end
