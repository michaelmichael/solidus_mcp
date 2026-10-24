# frozen_string_literal: true

module SolidusMcp
  module Tools
    class SearchOrders < Base
      tool_name :search_orders
      description "Search orders by exact number, state or store ID. Returns bounded order totals and statuses without customer contact information."
      category "Orders"
      permission "search_orders"
      read_only true
      ability :read, "Spree::Order"
      input :number, type: "string", minLength: 1, maxLength: 100
      input :state, type: "string", enum: %w[cart address delivery payment confirm complete canceled resumed]
      input :store_id, type: "integer", minimum: 1
      pagination

      protected

      def call(number: nil, state: nil, store_id: nil, after_id: 0, limit: 25)
        orders = policy.scope(Spree::Order)
        orders = orders.where(number: number) if number
        orders = orders.where(state: state) if state
        orders = orders.where(store_id: store_id) if store_id
        page(orders, after_id: after_id, limit: limit) { |order| serializers.order(order) }
      end
    end
  end
end
