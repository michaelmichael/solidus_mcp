# frozen_string_literal: true

module SolidusMcp
  class Credential
    SCOPES = %w[mcp:read mcp:write].freeze
    attr_reader :token, :user

    def self.authenticate(bearer)
      return if bearer.blank?
      token = Doorkeeper::AccessToken.by_token(bearer)
      return unless token
      user = Spree.user_class.find_by(id: token.resource_owner_id)
      credential = new(token, user)
      credential if credential.active?
    end

    def initialize(token, user)
      @token = token
      @user = user
    end

    def active?
      token.reload
      user&.reload
      token.accessible? && token.application.present? && user&.admin? &&
        token.resource == SolidusMcp.configuration.endpoint_url &&
        (token.scopes.to_a & SCOPES).any?
    rescue ActiveRecord::RecordNotFound
      false
    end

    def permits?(scope)
      token.scopes.include?(scope)
    end
  end
end
