# frozen_string_literal: true

module SolidusMcp
  module Tools
    class RefundPayment < Base
      tool_name :refund_payment
      description "Refund an explicit payment amount and currency through Solidus. Requires refund_reason_id and an idempotency key. Uncertain gateway outcomes block further external operations on the order until reconciled."
      category "Orders"
      permission "refund_payment"
      read_only false
      audit_action "create"
      ability :update, "Spree::Order"
      ability :update, "Spree::Payment"
      ability :read, "Spree::RefundReason"
      ability :create, "Spree::Refund"
      input :payment_id, type: "integer", minimum: 1, required: true
      input :refund_reason_id, type: "integer", minimum: 1, required: true
      input :currency, type: "string", pattern: "^[A-Z]{3}$", required: true
      input :amount, type: "string", required: true
      input :idempotency_key, type: "string", minLength: 1, maxLength: 128, required: true

      protected

      def call(payment_id:, refund_reason_id:, currency:, amount:, idempotency_key:)
        unless amount.match?(/\A(?:0|[1-9][0-9]{0,7})(?:\.[0-9]{1,2})?\z/) && BigDecimal(amount).positive?
          raise ToolError, "Amount must be a positive decimal string with at most two decimal places"
        end
        payment = policy.scope(Spree::Payment, :update)
          .where(order_id: policy.scope(Spree::Order, :update).select(:id)).find(payment_id)
        order = payment.order
        reason = policy.authorize_record!(:read, policy.scope(Spree::RefundReason).find(refund_reason_id))
        refund = Spree::Refund.new(payment_id: payment.id, refund_reason_id: reason.id, amount: BigDecimal(amount))
        policy.authorize_record!(:create, refund)
        policy.authorize_record!(:update, payment.order)
        unless currency.match?(/\A[A-Z]{3}\z/) && payment.currency == currency && refund.money.cents == BigDecimal(amount) * refund.money.currency.subunit_to_unit
          raise ToolError, "Currency must match the payment and support the requested cent precision"
        end
        request = ToolRequestExecution.new(credential, operation: "refund_payment", key: idempotency_key,
          payload: {payment_id: payment_id, refund_reason_id: refund_reason_id, currency: currency, amount: amount})
        request.external(guard_key: "order:#{order.id}") do |effects|
          order.with_lock do
            payment.with_lock do
              authorize!
              raise ToolError, "Payment order changed; retrieve it again" unless payment.order_id == order.id
              policy.authorize_record!(:update, payment.order)
              policy.authorize_record!(:update, payment)
              policy.authorize_record!(:read, reason.reload)
              unless payment.completed? && payment.currency == currency && BigDecimal(amount) <= payment.credit_allowed
                raise ToolError, "Payment is not refundable for the requested amount and currency"
              end
              refund = Spree::Refund.new(payment_id: payment.id, refund_reason_id: reason.id, amount: BigDecimal(amount))
              policy.authorize_record!(:create, refund)
              refund.save!
              effects.call
              refund.perform!
              {refund_id: refund.id, payment_id: payment.id, amount: refund.amount.to_s("F"), currency: currency, refunded: true}
            end
          end
        end
      end
    end
  end
end
