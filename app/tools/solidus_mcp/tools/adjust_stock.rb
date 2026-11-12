# frozen_string_literal: true

module SolidusMcp
  module Tools
    class AdjustStock < Base
      tool_name :adjust_stock
      description "Apply a signed stock movement to an existing variant/location stock item. Requires a reason and a connection-scoped idempotency key; retry with identical inputs. Solidus validations and backorder processing apply."
      category "Inventory"
      permission "adjust_stock"
      read_only false
      ability :read, "Spree::Product"
      ability :read, "Spree::Variant"
      ability :read, "Spree::StockLocation"
      ability :update, "Spree::StockItem"
      ability :create, "Spree::StockMovement"
      input :variant_id, type: "integer", minimum: 1, required: true
      input :stock_location_id, type: "integer", minimum: 1, required: true
      input :quantity, type: "integer", minimum: -2147483647, maximum: 2147483647,
        not: {const: 0}, required: true
      input :reason, type: "string", minLength: 1, maxLength: 1000, required: true
      input :idempotency_key, type: "string", minLength: 1, maxLength: 128,
        pattern: "^[A-Za-z0-9_.:-]+$", required: true

      protected

      def call(variant_id:, stock_location_id:, quantity:, reason:, idempotency_key:)
        raise ToolError, "Reason must not be blank" if reason.strip.empty?
        unless idempotency_key.match?(/\A[A-Za-z0-9_.:-]+\z/)
          raise ToolError, "Invalid idempotency key"
        end
        connection = ConnectionPolicy.find_by!(application_id: credential.token.application_id, user_id: credential.user.id)
        request = {variant_id: variant_id, stock_location_id: stock_location_id, quantity: quantity, reason: reason}
        StockAdjustment.transaction do
          # The database unique index serializes first use of a key across
          # processes. Failed movements roll back this row as well as the stock.
          adjustment = StockAdjustment.create_or_find_by!(connection_policy_id: connection.id, idempotency_key: idempotency_key) do |record|
            record.assign_attributes(request)
          end
          adjustment.with_lock do
            authorize!
            unless adjustment.attributes.symbolize_keys.slice(*request.keys) == request
              raise ToolError, "Idempotency key was already used with different inputs"
            end
            item = policy.scope(Spree::StockItem, :update)
              .where(variant_id: variants.where(id: variant_id).select(:id),
                stock_location_id: policy.scope(Spree::StockLocation).where(id: stock_location_id).select(:id)).sole
            item.with_lock do
              unless item.variant_id == variant_id && item.stock_location_id == stock_location_id
                raise ToolError, "Stock item context changed; retrieve inventory again"
              end
              if adjustment.result && adjustment.result["stock_item_id"] != item.id
                raise ToolError, "Stock item was replaced after this request completed"
              end
              # Match Solidus's stock-item -> variant lock order. Keep inventory
              # tracking stable while the movement callback runs.
              item.variant.with_lock do
                authorize!
                authorize_stock!(item)
                movement = Spree::StockMovement.new(stock_item: item, quantity: quantity, originator: adjustment)
                policy.authorize_record!(:create, movement)
                unless adjustment.result
                  unless item.should_track_inventory?
                    raise ToolError, "Inventory tracking must be enabled for this variant and store"
                  end
                  unless item.stock_location.active?
                    raise ToolError, "Stock location must be active"
                  end
                  before = item.count_on_hand
                  unless (before + quantity).between?(-2147483648, 2147483647)
                    raise ToolError, "Resulting stock count exceeds the supported integer range"
                  end
                  movement.save!
                  item.reload
                  authorize_stock!(item)
                  adjustment.update!(stock_movement: movement, result: {
                    stock_movement_id: movement.id, stock_item_id: item.id,
                    variant_id: variant_id, stock_location_id: stock_location_id,
                    quantity: quantity, count_on_hand_before: before,
                    count_on_hand_after: item.count_on_hand
                  })
                end
                adjustment.result.symbolize_keys
              end
            end
          end
        end
      end

      def authorize_stock!(item)
        policy.authorize_record!(:read, item.variant.product)
        policy.authorize_record!(:read, item.variant)
        policy.authorize_record!(:read, item.stock_location)
        policy.authorize_record!(:update, item)
        policy.authorize_record!(:update, item, attribute: :count_on_hand)
      end
    end
  end
end
