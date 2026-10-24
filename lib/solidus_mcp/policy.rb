# frozen_string_literal: true

module SolidusMcp
  class Policy
    def initialize(credential)
      @credential = credential
    end

    def allowed?(tool)
      authorize!(tool)
      true
    rescue AccessDenied
      false
    end

    def authorize!(tool)
      raise AccessDenied, "Unknown MCP tool" unless tool && SolidusMcp.registry.tools[tool.name].equal?(tool)
      raise AccessDenied, "Credential is no longer active" unless @credential.active?
      connection = ConnectionPolicy.find_by(application_id: @credential.token.application_id,
        user_id: @credential.user.id)
      raise AccessDenied, "Connection is disabled" if connection && (!connection.enabled? || connection.deleted_at?)
      raise AccessDenied, "Tool permission is not enabled" unless connection&.permissions&.include?(tool.permission)
      missing = tool.scopes.reject { |scope| @credential.permits?(scope) }
      raise InsufficientScope.new(missing) if missing.any?
      # Build abilities afresh: a reused server must not retain removed roles.
      @ability = Spree::Ability.new(@credential.user)
      tool.abilities.each do |action, model|
        raise AccessDenied, "Solidus permission denied" unless ability.can?(action, model.constantize)
      end
      true
    end

    def authorize_record!(action, record)
      raise AccessDenied, "Record is unavailable" unless ability.can?(action, record)
      record
    end

    def scope(model, action = :read)
      model.accessible_by(ability, action)
    end

    private

    def ability
      @ability ||= Spree::Ability.new(@credential.user)
    end
  end
end
