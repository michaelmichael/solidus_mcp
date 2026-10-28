# frozen_string_literal: true

module SolidusMcp
  module Tools
    class SearchInventory < Base
      tool_name :search_inventory
      description "Search stock levels by variant SKU or product name, with keyset pagination."
      category "Inventory"
      permission "search_inventory"
      read_only true
      ability :read, "Spree::Product"
      ability :read, "Spree::Variant"
      ability :read, "Spree::StockItem"
      ability :read, "Spree::StockLocation"
      input :query, type: "string", minLength: 1, maxLength: 100, required: true
      pagination

      protected

      def call(query:, after_id: 0, limit: 25)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        matching = variants.joins(:product).where("spree_variants.sku ILIKE ? OR spree_products.name ILIKE ?", pattern, pattern)
        page(stock_items.where(variant_id: matching.select(:id)), after_id: after_id, limit: limit) { |item| serializers.inventory(item) }
      end
    end
  end
end
