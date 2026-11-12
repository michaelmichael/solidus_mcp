# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ListStockLocations < Base
      tool_name :list_stock_locations
      description "Discover authorized stock location IDs, names, and operational flags, including inactive locations."
      category "Inventory"
      permission "list_stock_locations"
      read_only true
      ability :read, "Spree::StockLocation"
      pagination

      protected

      def call(after_id: 0, limit: 25)
        page(policy.scope(Spree::StockLocation), after_id: after_id, limit: limit) do |location|
          {id: location.id, name: location.name, active: location.active,
           default: location.default, fulfillable: location.fulfillable,
           backorderable_default: location.backorderable_default,
           propagate_all_variants: location.propagate_all_variants,
           restock_inventory: location.restock_inventory}
        end
      end
    end
  end
end
