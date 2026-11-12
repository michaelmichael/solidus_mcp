# frozen_string_literal: true

module SolidusMcp
  class OrderWorkflowAuthorization
    def initialize(policy)
      @policy = policy
    end

    def shipping(shipment, tracking: shipment.tracking, notify_customer: true)
      @policy.authorize_record!(:update, shipment.order)
      @policy.authorize_record!(:ship, shipment)
      @policy.authorize_record!(:read, shipment.stock_location)
      @policy.authorize_record!(:read, shipment.order.ship_address)
      @policy.authorize_record!(:read, shipment.shipping_method)
      shipment.inventory_units.each do |unit|
        @policy.authorize_record!(:update, unit)
        @policy.authorize_record!(:read, unit.variant)
        @policy.authorize_record!(:read, unit.variant.product)
      end
      carton = Spree::Carton.new(stock_location_id: shipment.stock_location_id, address_id: shipment.order.ship_address_id,
        shipping_method_id: shipment.shipping_method&.id, shipped_at: Time.current,
        tracking: tracking, suppress_email: !notify_customer)
      # Set the authorization preview's collection without assigning inverse
      # carton links to live inventory units before the real workflow runs.
      carton.association(:inventory_units).target = shipment.inventory_units.select(&:on_hand?)
      @policy.authorize_record!(:create, carton)
    end

    def cancellation(order)
      @policy.authorize_record!(:cancel, order)
      order.shipments.each do |shipment|
        @policy.authorize_record!(:cancel, shipment)
        @policy.authorize_record!(:read, shipment.stock_location)
        shipment.inventory_units.each do |unit|
          @policy.authorize_record!(:update, unit)
          @policy.authorize_record!(:read, unit.variant)
          @policy.authorize_record!(:read, unit.variant.product)
        end
        Spree::ShippingManifest.new(inventory_units: shipment.inventory_units).items.each do |manifest|
          item = Spree::StockItem.find_by!(variant_id: manifest.variant.id, stock_location_id: shipment.stock_location_id)
          on_hand = manifest.states["on_hand"].to_i
          backordered = manifest.states["backordered"].to_i
          next if on_hand.zero? && backordered.zero?
          @policy.authorize_record!(:update, item, attribute: :count_on_hand)
          if on_hand.positive?
            @policy.authorize_record!(:create, Spree::StockMovement.new(stock_item_id: item.id, quantity: on_hand, originator: shipment))
            item.backordered_inventory_units.limit(on_hand).each do |backorder|
              @policy.authorize_record!(:update, backorder)
              @policy.authorize_record!(:update, backorder.order)
            end
          end
          original_count = item.count_on_hand
          begin
            item[:count_on_hand] += backordered + (item.should_track_inventory? ? on_hand : 0)
            @policy.authorize_record!(:update, item, attribute: :count_on_hand)
          ensure
            item[:count_on_hand] = original_count
          end
        end
      end
      order.payments.each do |payment|
        next if payment.fully_refunded? || !(payment.pending? || payment.completed?)
        @policy.authorize_record!(:update, payment)
        @policy.authorize_record!(:cancel, payment)
        reason = Spree::RefundReason.find_by(name: Spree::Payment::Cancellation::DEFAULT_REASON)
        if reason
          @policy.authorize_record!(:read, reason)
        else
          reason = Spree::RefundReason.new(name: Spree::Payment::Cancellation::DEFAULT_REASON)
          @policy.authorize_record!(:create, reason)
        end
        @policy.authorize_record!(:create, Spree::Refund.new(payment_id: payment.id, reason: reason, amount: payment.credit_allowed))
      end
    end
  end
end
