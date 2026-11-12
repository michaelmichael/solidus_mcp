# frozen_string_literal: true

class CreateSolidusMcpStockAdjustments < ActiveRecord::Migration[7.2]
  def change
    create_table :solidus_mcp_stock_adjustments do |t|
      t.references :connection_policy, null: false, foreign_key: {to_table: :solidus_mcp_connection_policies}, index: false
      t.string :idempotency_key, null: false, limit: 128
      t.bigint :variant_id, null: false
      t.bigint :stock_location_id, null: false
      t.integer :quantity, null: false
      t.string :reason, null: false, limit: 1000
      t.references :stock_movement, foreign_key: {to_table: :spree_stock_movements}
      t.jsonb :result
      t.timestamps
    end
    add_index :solidus_mcp_stock_adjustments, [:connection_policy_id, :idempotency_key],
      unique: true, name: "index_mcp_stock_adjustments_on_request"
  end
end
