# frozen_string_literal: true

module SolidusMcp
  # Fixed public representations. Related records are checked separately.
  class Serializers
    def initialize(policy)
      @policy = policy
    end

    def product(record)
      @policy.authorize_record!(:read, record)
      record.attributes.slice("id", "name", "slug", "description", "meta_title", "meta_description", "meta_keywords")
    end

    def variant(record)
      @policy.authorize_record!(:read, record.product)
      @policy.authorize_record!(:read, record)
      record.attributes.slice("id", "product_id", "sku", "is_master")
    end

    def price(record)
      variant(record.variant)
      @policy.authorize_record!(:read, record)
      {id: record.id, variant_id: record.variant_id, currency: record.currency,
       country_iso: record.country_iso, amount: record.amount&.to_s("F")}
    end

    def inventory(record)
      variant(record.variant)
      @policy.authorize_record!(:read, record.stock_location)
      @policy.authorize_record!(:read, record)
      {id: record.id, variant_id: record.variant_id, sku: record.variant.sku,
       stock_location_id: record.stock_location_id, count_on_hand: record.count_on_hand,
       backorderable: record.backorderable}
    end

    def order(record)
      @policy.authorize_record!(:read, record)
      status(record).merge(currency: record.currency, total: record.total.to_s("F"),
        item_total: record.item_total.to_s("F"), completed_at: record.completed_at&.iso8601)
    end

    def status(record)
      @policy.authorize_record!(:read, record)
      {id: record.id, number: record.number, state: record.state,
       payment_state: record.payment_state, shipment_state: record.shipment_state}
    end
  end
end
