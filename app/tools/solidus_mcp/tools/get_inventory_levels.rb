# frozen_string_literal: true

module SolidusMcp
  module Tools
    class GetInventoryLevels < Base
      tool_name :get_inventory_levels
      description "Read stock counts and backorderability by location for one variant. Does not reserve or adjust stock."
      category "Inventory"
      permission "get_inventory_levels"
      read_only true
      ability :read, "Spree::Product"
      ability :read, "Spree::Variant"
      ability :read, "Spree::StockItem"
      ability :read, "Spree::StockLocation"
      input :variant_id, type: "integer", minimum: 1, required: true
      pagination

      protected

      def call(variant_id:, after_id: 0, limit: 25)
        serializers.variant(variants.find(variant_id))
        page(stock_items.where(variant_id: variant_id), after_id: after_id, limit: limit) { |item| serializers.inventory(item) }
      end
    end
  end
end
