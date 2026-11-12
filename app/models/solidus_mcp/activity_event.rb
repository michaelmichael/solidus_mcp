# frozen_string_literal: true

module SolidusMcp
  class ActivityEvent < ActiveRecord::Base
    self.table_name = "solidus_mcp_activity_events"
    ACTIONS = %w[read create update delete unknown].freeze
    STATUSES = %w[started succeeded partial denied failed].freeze

    validates :event_id, :protocol_method, :started_at, presence: true
    validates :actor_role, inclusion: {in: %w[user admin superadmin unknown]}
    validates :action, inclusion: {in: ACTIONS}
    validates :status, inclusion: {in: STATUSES}

    def self.visible_to(actor)
      return none unless Administration.user?(actor)
      return all if Administration.superadmin?(actor)
      if Administration.administrator?(actor)
        where(actor_role: "user").where.not(user_id: Administration.privileged_user_ids).or(where(user_id: actor.id))
      else
        where(user_id: actor.id)
      end
    end

    # Identity, tool metadata and targets cannot be edited through model writes.
    # The recorder completes a started event once through the narrow method below.
    def readonly?
      persisted?
    end

    def finish!(status:, duration_ms:, error_class: nil, result_ids: {})
      raise ArgumentError, "Invalid final audit status" unless %w[succeeded partial denied failed].include?(status)
      self.class.where(id: id, status: "started").update_all(status: status,
        finished_at: Time.current, duration_ms: duration_ms, error_class: error_class,
        resource_ids: resource_ids.merge(result_ids.empty? ? {} : {"result" => result_ids}))
    end
  end
end
