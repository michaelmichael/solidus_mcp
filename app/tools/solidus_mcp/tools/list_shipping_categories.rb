# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ListShippingCategories < Base
      tool_name :list_shipping_categories
      description "Discover authorized shipping category IDs and names for product creation."
      category "Products"
      permission "list_shipping_categories"
      read_only true
      ability :read, "Spree::ShippingCategory"
      pagination

      protected

      def call(after_id: 0, limit: 25)
        records = policy.scope(Spree::ShippingCategory)
        page(records, after_id: after_id, limit: limit) do |record|
          {id: record.id, name: record.name}
        end
      end
    end
  end
end
