# frozen_string_literal: true

module SolidusMcp
  module Tools
    class GetOrder < Base
      tool_name :get_order
      description "Retrieve order totals, status and up to 100 authorized line items. Includes a truncation indicator."
      category "Orders"
      permission "get_order"
      read_only true
      ability :read, "Spree::Order"
      ability :read, "Spree::LineItem"
      input :order_id, type: "integer", minimum: 1, required: true

      protected

      def call(order_id:)
        order = policy.scope(Spree::Order).find(order_id)
        data = serializers.order(order)
        data[:line_items] = policy.scope(Spree::LineItem).where(order_id: order.id).order(:id).limit(100).map do |item|
          policy.authorize_record!(:read, item)
          {id: item.id, variant_id: item.variant_id, quantity: item.quantity, price: item.price.to_s("F")}
        end
        data[:line_items_truncated] = policy.scope(Spree::LineItem).where(order_id: order.id).count > 100
        data
      end
    end
  end
end
