# frozen_string_literal: true

class CreateSolidusMcpAdministrators < ActiveRecord::Migration[7.2]
  def change
    create_table :solidus_mcp_administrators do |t|
      t.bigint :user_id, null: false
      t.boolean :enabled, default: true, null: false
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
    add_index :solidus_mcp_administrators, :user_id, unique: true

    create_table :solidus_mcp_administrator_changes do |t|
      t.references :administrator, null: false, foreign_key: {to_table: :solidus_mcp_administrators}
      t.bigint :actor_id, null: false
      t.boolean :previous_enabled, null: false
      t.boolean :enabled, null: false
      t.timestamps
    end
  end
end
