# frozen_string_literal: true

module SolidusMcp
  class EndpointController < ActionController::API
    MAX_REQUEST_BYTES = 1.megabyte

    include HttpAccess
    prepend_around_action :audit_request_context, except: :preflight
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

    def audit_request_context
      payload = nil
      if request.post? && request.media_type == "application/json"
        body = request.body.read(MAX_REQUEST_BYTES + 1)
        request.body.rewind
        payload = parse_payload(body) if body.bytesize <= MAX_REQUEST_BYTES
      end
      AuditContext.set(request_id: request.request_id, event_count: 0, invocation: nil) do
        yield
      ensure
        # Authentication, scope challenges and transport checks can reject a
        # request before SDK dispatch. Record these when identity is known.
        if @audit_credential && payload.is_a?(Hash) && AuditContext.event_count.to_i.zero? && payload["method"].is_a?(String)
          params = payload["params"].is_a?(Hash) ? payload["params"] : {}
          method = payload["method"]
          method = "unknown" unless %w[tools/call tools/list initialize ping].include?(method)
          begin
            ActionAudit.capture(credential: @audit_credential, protocol_method: method,
              tool_name: params["name"], arguments: params["arguments"]) do |invocation|
              invocation.status = [401, 403].include?(response.status) ? "denied" : "failed"
              invocation.error_class = (invocation.status == "denied") ? "SolidusMcp::AccessDenied" : "MCP::ProtocolError"
            end
          rescue
            Rails.logger.error("Solidus MCP could not record a rejected request")
          end
        end
      end
    end

    def parse_payload(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def authenticate
      bearer = request.authorization&.match(/\ABearer ([^\s]+)\z/i)&.captures&.first
      @credential = Credential.authenticate(bearer)
      @audit_credential = @credential
      unless @credential
        token = Doorkeeper::AccessToken.by_token(bearer) if bearer.present?
        if token
          owner = Spree.user_class.find_by(id: token.resource_owner_id)
          @audit_credential = Credential.new(token, owner)
        end
        response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{SolidusMcp.configuration.endpoint_url}/metadata"))
        return head :unauthorized
      end
      connection = ConnectionPolicy.find_by(application_id: @credential.token.application_id, user_id: @credential.user.id)
      head :forbidden if connection && (!connection.enabled? || connection.deleted_at?)
    end
  end
end
