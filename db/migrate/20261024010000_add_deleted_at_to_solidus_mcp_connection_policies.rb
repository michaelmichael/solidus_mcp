# frozen_string_literal: true

class AddDeletedAtToSolidusMcpConnectionPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :solidus_mcp_connection_policies, :deleted_at, :datetime
  end
end
