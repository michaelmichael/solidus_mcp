# frozen_string_literal: true

class CreateSolidusMcpConnectionPolicies < ActiveRecord::Migration[7.1]
  def change
    create_table :solidus_mcp_connection_policies do |t|
      # Retain policy/audit identity when Doorkeeper purges a client. Like the
      # user/actor IDs below, this is intentionally not a cascading foreign key.
      t.references :application, null: false
      t.string :application_uid, null: false
      t.bigint :user_id, null: false
      t.jsonb :permissions, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.index [:application_id, :user_id], unique: true, name: "index_mcp_policies_on_connection"
    end

    create_table :solidus_mcp_policy_changes do |t|
      t.references :connection_policy, null: false, foreign_key: {to_table: :solidus_mcp_connection_policies}, index: {name: "index_mcp_changes_on_policy"}
      t.bigint :actor_id, null: false
      t.jsonb :previous_values, null: false
      t.jsonb :new_values, null: false
      t.timestamps
    end
  end
end
