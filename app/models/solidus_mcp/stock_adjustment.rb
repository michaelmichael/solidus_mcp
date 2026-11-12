# frozen_string_literal: true

module SolidusMcp
  # Keep these records for as long as requests can be retried. Deleting them
  # removes the duplicate-request protection for their connection and key.
  class StockAdjustment < ActiveRecord::Base
    self.table_name = "solidus_mcp_stock_adjustments"

    belongs_to :connection_policy, class_name: "SolidusMcp::ConnectionPolicy"
    belongs_to :stock_movement, class_name: "Spree::StockMovement", optional: true

    validates :idempotency_key, presence: true, length: {maximum: 128}
    validates :reason, presence: true, length: {maximum: 1000}
    validates :variant_id, :stock_location_id, :quantity, presence: true
  end
end
