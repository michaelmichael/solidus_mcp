# frozen_string_literal: true

class CreateSolidusMcpToolRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :solidus_mcp_tool_requests do |t|
      t.references :connection_policy, null: false, foreign_key: {to_table: :solidus_mcp_connection_policies}, index: false
      t.string :operation, null: false
      t.string :idempotency_key, null: false, limit: 128
      t.string :guard_key
      t.jsonb :payload, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :result
      t.timestamps
    end
    add_index :solidus_mcp_tool_requests, [:connection_policy_id, :operation, :idempotency_key], unique: true, name: "index_mcp_tool_requests_on_key"
    add_index :solidus_mcp_tool_requests, :guard_key, unique: true,
      where: "status IN ('processing', 'uncertain')", name: "index_mcp_tool_requests_on_active_target"
  end
end
