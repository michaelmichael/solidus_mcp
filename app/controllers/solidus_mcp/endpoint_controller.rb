# frozen_string_literal: true

module SolidusMcp
  class EndpointController < ActionController::API
    MAX_REQUEST_BYTES = 1.megabyte

    include HttpAccess
    before_action :authenticate, except: :preflight

    def handle
      # A scope challenge belongs to HTTP, not an MCP tool error. Inspect only
      # the tool identity; SDK parsing/validation still owns the protocol.
      if request.post? && request.media_type == "application/json"
        body = request.body.read(MAX_REQUEST_BYTES + 1)
        request.body.rewind
        return head :payload_too_large if body.bytesize > MAX_REQUEST_BYTES
        payload = parse_payload(body)
        if payload.is_a?(Hash) && payload["method"] == "tools/call" && payload["params"].is_a?(Hash)
          tool = SolidusMcp.registry.tools[payload["params"]["name"]]
          begin
            Policy.new(@credential).authorize!(tool) if tool
          rescue InsufficientScope => e
            response.set_header("WWW-Authenticate", %(Bearer error="insufficient_scope", scope="#{e.scopes.join(" ")}", resource_metadata="#{SolidusMcp.configuration.endpoint_url}/metadata"))
            return render json: {error: "insufficient_scope"}, status: :forbidden
          rescue AccessDenied
            # Normal tool permission failures remain protocol errors.
          end
        end
      end
      config = SolidusMcp.configuration
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        Server.build(credential: @credential), stateless: true, serve_subscriptions_listen: false,
        allowed_hosts: [URI(config.endpoint_url).host], allowed_origins: config.allowed_origins
      )
      status, headers, body = transport.handle_request(request)
      self.status = status
      headers.each { |key, value| response.set_header(key, value) }
      self.response_body = body
      response.set_header("Cache-Control", "no-store")
    end

    private

    def parse_payload(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def authenticate
      bearer = request.authorization&.match(/\ABearer ([^\s]+)\z/i)&.captures&.first
      @credential = Credential.authenticate(bearer)
      unless @credential
        response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{SolidusMcp.configuration.endpoint_url}/metadata"))
        return head :unauthorized
      end
      connection = ConnectionPolicy.find_by(application_id: @credential.token.application_id, user_id: @credential.user.id)
      head :forbidden if connection && !connection.enabled?
    end
  end
end
