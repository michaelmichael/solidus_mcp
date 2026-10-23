# frozen_string_literal: true

module SolidusMcp
  class Policy
    def initialize(credential, registry: SolidusMcp.registry)
      @credential = credential
      @registry = registry
    end

    def allowed?(tool)
      denial(tool).nil?
    end

    def authorize!(tool)
      reason = denial(tool)
      raise AccessDenied, reason if reason
    end

    def authorize_record!(action, record)
      raise AccessDenied, "This user cannot #{action} this record" unless ability.can?(action, record)
      record
    end

    def scope(model, action = :read)
      model.accessible_by(ability, action)
    end

    private

    def ability
      @ability ||= Spree::Ability.new(@credential.user)
    end

    def denial(tool)
      return "Unknown MCP operation" unless tool && @registry.tools[tool.name].equal?(tool)
      return "This credential is no longer active" unless @credential.active?
      missing_scope = tool.scopes.find { |scope| !@credential.permits?(scope) }
      return "This credential does not permit #{missing_scope}" if missing_scope

      # Read on each call: a policy edit applies even to an already-built server
      # or a service instance reused by a caller. Token rotation keeps this key.
      connection = ConnectionPolicy.find_by(application_id: @credential.token.application_id,
        user_id: @credential.user.id)
      return "This MCP connection is disabled" if connection && !connection.enabled?
      grants = connection ? connection.permissions : SolidusMcp.default_permissions
      missing = tool.permissions.find { |key| !grants.include?(key) }
      return "This connection does not permit #{missing}" if missing

      tool.permissions.each do |key|
        permission = @registry.permissions.fetch(key)
        unless ability.can?(permission.ability_action, permission.model_name.constantize)
          return "This user does not permit #{key}"
        end
      end
      nil
    end
  end
end
