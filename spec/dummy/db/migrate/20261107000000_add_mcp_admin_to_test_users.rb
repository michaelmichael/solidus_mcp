# frozen_string_literal: true

class AddMcpAdminToTestUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :test_users, :mcp_admin, :boolean, default: false, null: false
  end
end
