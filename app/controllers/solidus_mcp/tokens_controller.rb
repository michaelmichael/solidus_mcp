# frozen_string_literal: true

module SolidusMcp
  class TokensController < Doorkeeper::TokensController
    include HttpAccess
    before_action :validate_resource

    private

    def validate_resource
      return if action_name == "revoke"
      expected = SolidusMcp.configuration.endpoint_url
      return render json: {error: "invalid_target"}, status: :bad_request unless params[:resource] == expected
      source = case params[:grant_type]
      when "authorization_code" then Doorkeeper::AccessGrant.by_token(params[:code])
      when "refresh_token" then Doorkeeper::AccessToken.by_refresh_token(params[:refresh_token])
      end
      if source && source.resource != expected
        render json: {error: "invalid_grant"}, status: :bad_request
      end
    end
  end
end
