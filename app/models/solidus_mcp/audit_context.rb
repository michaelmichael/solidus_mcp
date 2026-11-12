# frozen_string_literal: true

module SolidusMcp
  class AuditContext < ActiveSupport::CurrentAttributes
    attribute :invocation, :request_id, :event_count
  end
end
