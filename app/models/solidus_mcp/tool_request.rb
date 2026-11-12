# frozen_string_literal: true

module SolidusMcp
  class ToolRequest < ActiveRecord::Base
    self.table_name = "solidus_mcp_tool_requests"
    belongs_to :connection_policy, class_name: "SolidusMcp::ConnectionPolicy"
    validates :operation, :idempotency_key, presence: true
    validates :idempotency_key, length: {maximum: 128}
  end
end
