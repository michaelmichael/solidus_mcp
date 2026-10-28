# frozen_string_literal: true

module SolidusMcp
  class MetadataController < ActionController::API
    include HttpAccess

    def resource
      render json: {resource: SolidusMcp.configuration.endpoint_url,
                    authorization_servers: [SolidusMcp.configuration.issuer_url],
                    scopes_supported: Credential::SCOPES, bearer_methods_supported: ["header"]}
    end

    def authorization_server
      base = SolidusMcp.configuration.endpoint_url
      render json: {issuer: SolidusMcp.configuration.issuer_url,
                    authorization_endpoint: "#{base}/oauth/authorize", token_endpoint: "#{base}/oauth/token",
                    revocation_endpoint: "#{base}/oauth/revoke", registration_endpoint: "#{base}/oauth/register",
                    response_types_supported: ["code"], grant_types_supported: %w[authorization_code refresh_token],
                    token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post none],
                    code_challenge_methods_supported: ["S256"], scopes_supported: Credential::SCOPES}
    end
  end
end
