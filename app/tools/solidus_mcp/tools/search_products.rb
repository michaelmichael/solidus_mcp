# frozen_string_literal: true

module SolidusMcp
  module Tools
    class SearchProducts < Base
      tool_name :search_products
      description "Search authorized products by product name or variant SKU, with keyset pagination."
      category "Products"
      permission "search_products"
      read_only true
      ability :read, "Spree::Product"
      ability :read, "Spree::Variant"
      input :query, type: "string", minLength: 1, maxLength: 100, required: true
      pagination

      protected

      def call(query:, after_id: 0, limit: 25)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        sku_ids = variants.where("spree_variants.sku ILIKE ?", pattern).select(:product_id)
        products = policy.scope(Spree::Product)
        matching = products.where("spree_products.name ILIKE ?", pattern).or(products.where(id: sku_ids))
        page(matching, after_id: after_id, limit: limit) { |product| serializers.product(product) }
      end
    end
  end
end
