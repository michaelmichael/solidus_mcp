# frozen_string_literal: true

module SolidusMcp
  class Administrator < ActiveRecord::Base
    self.table_name = "solidus_mcp_administrators"
    attr_readonly :user_id
    belongs_to :user, class_name: Spree.user_class.name
    has_many :role_changes, class_name: "SolidusMcp::AdministratorChange", dependent: :restrict_with_exception

    validates :user_id, uniqueness: true
    validates :enabled, inclusion: {in: [true, false]}

    def change!(actor:, enabled:, lock_version:)
      transaction do
        Administration.lock_users!(actor, user)
        Administration.authorize_assignment!(actor, user)
        unless [true, false].include?(enabled)
          raise ArgumentError, "enabled must be true or false"
        end
        if enabled && !user.admin?
          errors.add(:user, "must be a Solidus administrator")
          raise ActiveRecord::RecordInvalid.new(self)
        end
        if new_record? != (lock_version == -1)
          raise ActiveRecord::StaleObjectError.new(self, "update")
        end
        previous = persisted? ? enabled_in_database : false
        self.lock_version = new_record? ? 0 : lock_version
        self.enabled = enabled
        save!
        role_changes.create!(actor_id: actor.id, previous_enabled: previous, enabled: enabled) if previous != enabled
      end
    end
  end
end
