# frozen_string_literal: true

module SolidusMcp
  class ConnectionPolicy < ActiveRecord::Base
    self.table_name = "solidus_mcp_connection_policies"
    belongs_to :application, class_name: "Doorkeeper::Application"
    belongs_to :user, class_name: Spree.user_class.name
    has_many :policy_changes, class_name: "SolidusMcp::PolicyChange", dependent: :restrict_with_exception

    validates :user_id, uniqueness: {scope: :application_id}
    validates :enabled, inclusion: {in: [true, false]}
    validates :application_uid, presence: true
    validate :known_permissions
    before_validation :retain_application_uid, on: :create

    # Management writes and their audit must commit together. lock_version
    # prevents an older form from restoring permissions another admin removed.
    def change!(actor:, permissions:, enabled:, lock_version:, deleted_at: nil)
      transaction do
        # -1 identifies the unsaved default policy. Version 0 must not let a
        # default-policy form overwrite someone else's first explicit policy.
        if new_record? != (lock_version == -1)
          raise ActiveRecord::StaleObjectError.new(self, "update")
        end
        self.lock_version = new_record? ? 0 : lock_version
        previous = persisted? ? attributes.slice("permissions", "enabled", "deleted_at") :
          {"permissions" => [], "enabled" => true, "deleted_at" => nil}
        assign_attributes(permissions: permissions.uniq.sort, enabled: enabled, deleted_at: deleted_at)
        save!
        current = attributes.slice("permissions", "enabled", "deleted_at")
        policy_changes.create!(actor_id: actor.id, previous_values: previous, new_values: current) if previous != current
      end
    end

    def delete_permissions!(actor:, lock_version:)
      change!(actor: actor, permissions: [], enabled: false, lock_version: lock_version, deleted_at: Time.current)
    end

    private

    def retain_application_uid
      self.application_uid = application&.uid
    end

    def known_permissions
      valid = permissions.is_a?(Array) && permissions.all? { |key| key.is_a?(String) && (SolidusMcp.registry.permissions.include?(key) || Array(permissions_in_database).include?(key)) }
      errors.add(:permissions, "contain an unknown operation") unless valid
    end
  end
end
