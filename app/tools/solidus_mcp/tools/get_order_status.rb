# frozen_string_literal: true

module SolidusMcp
  module Tools
    class GetOrderStatus < Base
      tool_name :get_order_status
      description "Retrieve the order, payment and shipment states for an order ID."
      category "Orders"
      permission "get_order_status"
      read_only true
      ability :read, "Spree::Order"
      input :order_id, type: "integer", minimum: 1, required: true

      protected

      def call(order_id:)
        serializers.status(policy.scope(Spree::Order).find(order_id))
      end
    end
  end
end
