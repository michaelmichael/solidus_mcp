# frozen_string_literal: true

module SolidusMcp
  class PolicyChange < ActiveRecord::Base
    self.table_name = "solidus_mcp_policy_changes"
    belongs_to :connection_policy, class_name: "SolidusMcp::ConnectionPolicy"
    belongs_to :actor, class_name: Spree.user_class.name
  end
end
