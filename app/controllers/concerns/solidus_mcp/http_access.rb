# frozen_string_literal: true

module SolidusMcp
  module HttpAccess
    extend ActiveSupport::Concern

    included do
      before_action :prepare_mcp_request
    end

    def preflight
      response.set_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
      response.set_header("Access-Control-Allow-Headers", "Content-Type, Authorization, MCP-Protocol-Version, MCP-Session-Id")
      head :no_content
    end

    private

    def prepare_mcp_request
      config = SolidusMcp.configuration
      return head :not_found unless config.enabled?
      config.validate!
      response.set_header("Cache-Control", "no-store")
      response.set_header("Vary", "Origin")
      origin = request.headers["Origin"]
      if origin.present?
        return head :forbidden unless config.allowed_origins.include?(origin)
        response.set_header("Access-Control-Allow-Origin", origin)
        response.set_header("Access-Control-Expose-Headers", "WWW-Authenticate, MCP-Session-Id")
      end
    end
  end
end
