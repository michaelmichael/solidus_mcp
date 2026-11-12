# frozen_string_literal: true

module SolidusMcp
  # Public SDK entry points cover schema rejection and undiscoverable tools,
  # which never reach a tool's Ruby implementation.
  class AuditedServer < MCP::Server
    def initialize(credential:, **options)
      @audit_credential = credential
      super(**options)
    end

    def handle(payload, **options)
      ActionAudit.protocol(credential: @audit_credential, payload: payload) { super }
    end

    def handle_json(payload, **options)
      parsed = begin
        JSON.parse(payload)
      rescue JSON::ParserError
        nil
      end
      ActionAudit.protocol(credential: @audit_credential, payload: parsed) { super }
    end
  end
end
