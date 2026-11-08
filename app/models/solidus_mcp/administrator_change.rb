# frozen_string_literal: true

module SolidusMcp
  class AdministratorChange < ActiveRecord::Base
    self.table_name = "solidus_mcp_administrator_changes"
    belongs_to :administrator, class_name: "SolidusMcp::Administrator"
  end
end
