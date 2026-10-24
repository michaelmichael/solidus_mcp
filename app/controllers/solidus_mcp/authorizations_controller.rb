# frozen_string_literal: true

module SolidusMcp
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    layout false
    before_action :validate_mcp_request
    helper_method :scope_options

    private

    def scope_options
      registered = @pre_auth.client.application.scopes.to_a
      configured = Doorkeeper.config.default_scopes.to_a | Doorkeeper.config.optional_scopes.to_a
      Credential::SCOPES & configured & (registered.empty? ? Credential::SCOPES : registered)
    end

    def validate_mcp_request
      return head :not_found unless SolidusMcp.configuration.enabled?
      return render json: {error: "invalid_target"}, status: :bad_request unless params[:resource] == SolidusMcp.configuration.endpoint_url
      if params.key?(:requested_scopes) || params.key?(:review_scopes)
        selected = params[:requested_scopes]
        unless action_name == "new" && request.get? && selected.is_a?(Array) && selected.any? &&
            selected.all? { |scope| scope.is_a?(String) } && (selected - Credential::SCOPES).empty?
          return render json: {error: "invalid_scope"}, status: :bad_request
        end
        # Review prepares a new consent summary, never a grant. Doorkeeper
        # still validates the client, callback and registered scope ceiling.
        params[:scope] = selected.uniq.join(" ")
      end
      scopes = params[:scope].presence || "mcp:read"
      unless scopes.is_a?(String) && scopes.split.any? && (scopes.split - Credential::SCOPES).empty?
        return render json: {error: "invalid_scope"}, status: :bad_request
      end
      params[:scope] = scopes
      unless params[:code_challenge_method] == "S256" && params[:code_challenge].to_s.match?(/\A[A-Za-z0-9_-]{43}\z/)
        render json: {error: "invalid_request", error_description: "S256 PKCE is required"}, status: :bad_request
      end
    end
  end
end
