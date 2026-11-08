# frozen_string_literal: true

module SolidusMcp
  module Administration
    module_function

    def user?(user)
      !!user&.admin?
    end

    def superadmin?(user)
      user?(user) && superadmin_user_ids.include?(user.id.to_s)
    end

    def administrator?(user)
      user?(user) && (superadmin?(user) || Administrator.exists?(user_id: user.id, enabled: true))
    end

    def role(user)
      return unless user?(user)
      return :superadmin if superadmin?(user)
      administrator?(user) ? :admin : :user
    end

    def superadmin_user_ids
      emails = Array(SolidusMcp.configuration.superadmin_emails).map { |email| email.to_s.strip.downcase }.uniq
      return [] if emails.empty?
      matches = Spree.user_class.where("LOWER(email) IN (?)", emails).pluck(:id, :email)
      # Fail closed for ambiguous login addresses, including case-only duplicates.
      matches.group_by { |_id, email| email.downcase }.values.filter_map do |accounts|
        accounts.first.first.to_s if accounts.one?
      end
    end

    def privileged_user_ids
      superadmin_user_ids | Administrator.where(enabled: true).pluck(:user_id).map(&:to_s)
    end

    def visible_connections(scope, actor)
      return scope if superadmin?(actor)
      return scope.where(resource_owner_id: actor.id) unless administrator?(actor)
      scope.where.not(resource_owner_id: privileged_user_ids).or(scope.where(resource_owner_id: actor.id))
    end

    def can_view?(actor, owner)
      user?(actor) && (actor.id == owner.id || can_manage?(actor, owner))
    end

    def can_manage?(actor, owner)
      return true if superadmin?(actor)
      administrator?(actor) && !administrator?(owner)
    end

    # Management writes lock the same user rows as role assignments, in stable
    # order, so a role change cannot race a grant to a newly privileged account.
    # Call within the management transaction; never use these locks for reads.
    def lock_users!(*users)
      unless users.all? { |user| user&.persisted? }
        raise AccessDenied, "An existing actor and connection owner are required"
      end
      ids = users.map(&:id).uniq.sort
      Spree.user_class.where(id: ids).order(:id).lock.load
      users.compact.each(&:reload)
    end

    def authorize_management!(actor, owner:, action: :update)
      actor&.reload
      owner.reload
      ability = Spree::Ability.new(actor)
      unless can_manage?(actor, owner) && ability.can?(:admin, :mcp_connections) && ability.can?(action, :mcp_connections)
        raise AccessDenied, "MCP administration access is required for this connection"
      end
    rescue ActiveRecord::RecordNotFound
      raise AccessDenied, "MCP administration access is required for this connection"
    end

    def authorize_assignment!(actor, owner)
      actor&.reload
      ability = Spree::Ability.new(actor)
      unless superadmin?(actor) && ability.can?(:admin, :mcp_administrators) && ability.can?(:update, :mcp_administrators)
        raise AccessDenied, "MCP superadministrator access is required to assign administrators"
      end
      if superadmin_user_ids.include?(owner.id.to_s)
        raise AccessDenied, "Superadministrators are designated in server configuration"
      end
    rescue ActiveRecord::RecordNotFound
      raise AccessDenied, "MCP superadministrator access is required to assign administrators"
    end
  end
end
