# frozen_string_literal: true

module SolidusMcp
  class RegistrationsController < ActionController::API
    include HttpAccess

    MAX_BODY_BYTES = 16.kilobytes

    wrap_parameters false
    before_action :prepare_registration
    rate_limit to: 20, within: 1.hour, name: "per-ip", store: ActionController::Base.cache_store,
      with: -> { registration_throttled }
    rate_limit to: 200, within: 1.hour, name: "global", by: -> { "all" }, store: ActionController::Base.cache_store,
      with: -> { registration_throttled }

    def create
      return render_error("invalid_client_metadata", "Use application/json", :unsupported_media_type) unless request.media_type == "application/json"

      body = request.body.read(MAX_BODY_BYTES + 1)
      return render_error("invalid_client_metadata", "Registration metadata is too large", :payload_too_large) if body.bytesize > MAX_BODY_BYTES

      render json: ClientRegistration.call(JSON.parse(body)), status: :created
    rescue JSON::ParserError
      render_error("invalid_client_metadata", "Expected a JSON object")
    rescue ClientRegistration::InvalidMetadata => e
      render_error(e.code, e.message)
    rescue ActiveRecord::RecordInvalid
      render_error("invalid_client_metadata", "Client metadata could not be registered")
    end

    private

    def prepare_registration
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      head :not_found unless SolidusMcp.configuration.enabled?
    end

    def registration_throttled
      response.set_header("Retry-After", "3600")
      render_error("temporarily_unavailable", "Too many client registrations; try again later", :too_many_requests)
    end

    def render_error(code, description, status = :bad_request)
      render json: {error: code, error_description: description}, status: status
    end
  end
end
