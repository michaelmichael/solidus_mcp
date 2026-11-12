# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ShipShipment < Base
      tool_name :ship_shipment
      description "Ship one ready shipment through Solidus carton fulfillment. Explicitly choose notify_customer; tracking is optional. Requires an idempotency key and record permissions for affected fulfillment records."
      category "Orders"
      permission "ship_shipment"
      read_only false
      ability :update, "Spree::Order"
      ability :ship, "Spree::Shipment"
      ability :update, "Spree::InventoryUnit"
      ability :create, "Spree::Carton"
      input :shipment_id, type: "integer", minimum: 1, required: true
      input :tracking, type: "string", minLength: 1, maxLength: 255
      input :notify_customer, type: "boolean", required: true
      input :idempotency_key, type: "string", minLength: 1, maxLength: 128, required: true

      protected

      def call(shipment_id:, notify_customer:, idempotency_key:, tracking: nil)
        shipment = policy.scope(Spree::Shipment, :ship)
          .where(order_id: policy.scope(Spree::Order, :update).select(:id)).find(shipment_id)
        order = shipment.order
        authorization = OrderWorkflowAuthorization.new(policy)
        authorization.shipping(shipment, tracking: tracking || shipment.tracking, notify_customer: notify_customer)
        request = ToolRequestExecution.new(credential, operation: "ship_shipment", key: idempotency_key,
          payload: {shipment_id: shipment_id, tracking: tracking, notify_customer: notify_customer})
        request.external(guard_key: "order:#{order.id}") do |effects|
          order.with_lock do
            shipment.with_lock do
              authorize!
              raise ToolError, "Shipment order changed; retrieve it again" unless shipment.order_id == order.id
              units = shipment.inventory_units.reload.to_a
              units.each(&:lock!)
              authorization.shipping(shipment, tracking: tracking || shipment.tracking, notify_customer: notify_customer)
              if shipment.shipped?
                if tracking && tracking != shipment.tracking
                  raise ToolError, "Shipment is already shipped with different tracking"
                end
              else
                eligible = shipment.state == "ready" && shipment.order.completed? && units.any?(&:on_hand?) &&
                  units.all? { |unit| unit.on_hand? || unit.shipped? || unit.canceled? }
                unless eligible
                  raise ToolError, "Shipment must be ready on a completed order, with shippable units and no backorders"
                end
                policy.authorize_record!(:update, shipment, attribute: :tracking) if tracking
                shipment.tracking = tracking if tracking
                policy.authorize_record!(:ship, shipment)
                policy.authorize_record!(:update, shipment, attribute: :tracking) if tracking
                shipment.suppress_mailer = !notify_customer
                effects.call
                shipment.ship!
              end
              {shipment_id: shipment.id, order_id: shipment.order_id, state: shipment.state, tracking: shipment.tracking}
            end
          end
        end
      end
    end
  end
end
