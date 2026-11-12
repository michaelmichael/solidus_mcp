# frozen_string_literal: true

module SolidusMcp
  module Tools
    class CancelOrder < Base
      tool_name :cancel_order
      description "Cancel a completed, cancellable order through Solidus, including shipment restocking and payment cancellation. Requires a reason and idempotency key; uncertain external outcomes require reconciliation."
      category "Orders"
      permission "cancel_order"
      read_only false
      ability :cancel, "Spree::Order"
      input :order_id, type: "integer", minimum: 1, required: true
      input :reason, type: "string", minLength: 1, maxLength: 1000, required: true
      input :idempotency_key, type: "string", minLength: 1, maxLength: 128, required: true

      protected

      def call(order_id:, reason:, idempotency_key:)
        raise ToolError, "Cancellation reason must not be blank" if reason.strip.empty?
        order = policy.scope(Spree::Order, :cancel).find(order_id)
        authorization = OrderWorkflowAuthorization.new(policy)
        authorization.cancellation(order)
        request = ToolRequestExecution.new(credential, operation: "cancel_order", key: idempotency_key,
          payload: {order_id: order_id, reason: reason})
        request.external(guard_key: "order:#{order.id}") do |effects|
          order.with_lock do
            authorize!
            order.shipments.reload.each(&:lock!)
            order.payments.reload.each(&:lock!)
            authorization.cancellation(order)
            unless order.canceled?
              unless order.can_cancel? && order.shipments.all? { |shipment| %w[pending ready].include?(shipment.state) }
                raise ToolError, "Order must be complete and every shipment must be pending or ready"
              end
              effects.call
              order.canceled_by(credential.user)
            end
            {order_id: order.id, state: order.state, canceled: true}
          end
        end
      end
    end
  end
end
