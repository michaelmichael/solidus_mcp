# frozen_string_literal: true

class CreateSolidusMcpActivityEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :solidus_mcp_activity_events do |t|
      # Preserve attribution when OAuth clients, tokens, or users are removed.
      t.bigint :user_id
      t.bigint :application_id
      t.bigint :token_id
      t.string :application_uid
      t.string :application_name
      t.string :event_id, null: false
      t.string :request_id
      t.string :protocol_method, null: false
      t.string :tool_name
      t.string :permission
      t.string :category
      t.string :action, null: false
      t.string :status, null: false, default: "started"
      t.jsonb :resource_ids, null: false, default: {}
      t.jsonb :changed_fields, null: false, default: []
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.bigint :duration_ms
      t.string :error_class
    end
    add_index :solidus_mcp_activity_events, :event_id, unique: true
    add_index :solidus_mcp_activity_events, :started_at
    add_index :solidus_mcp_activity_events, [:user_id, :started_at]
    add_index :solidus_mcp_activity_events, [:action, :started_at]
    add_index :solidus_mcp_activity_events, [:tool_name, :started_at]
    add_index :solidus_mcp_activity_events, [:status, :started_at]
  end
end
