# frozen_string_literal: true

class AddActorRoleToMcpActivityEvents < ActiveRecord::Migration[7.2]
  def change
    add_column :solidus_mcp_activity_events, :actor_role, :string, null: false, default: "unknown"
  end
end
