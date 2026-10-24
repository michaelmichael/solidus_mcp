# frozen_string_literal: true

module SolidusMcp
  class Server
    def self.build(credential:)
      policy = Policy.new(credential)
      tools = SolidusMcp.registry.tools.values.filter_map do |tool|
        next unless policy.allowed?(tool)
        MCP::Tool.define(name: tool.name, description: tool.description, input_schema: tool.input_schema,
          annotations: {read_only_hint: tool.read_only, destructive_hint: !tool.read_only,
                        idempotent_hint: tool.read_only, open_world_hint: false}) do |**arguments|
          arguments.delete(:server_context)
          policy.authorize!(tool)
          result = tool.class_name.constantize.execute(credential: credential, **arguments)
          MCP::Tool::Response.new([{type: "text", text: result.to_json}], structured_content: result)
        rescue AccessDenied, ToolError, MCP::Tool::InputSchema::ValidationError => e
          MCP::Tool::Response.new([{type: "text", text: e.message}], error: true)
        rescue ActiveRecord::RecordNotFound
          MCP::Tool::Response.new([{type: "text", text: "Record is unavailable"}], error: true)
        rescue ActiveRecord::RecordInvalid => e
          MCP::Tool::Response.new([{type: "text", text: e.record.errors.full_messages.to_sentence}], error: true)
        end
      end
      MCP::Server.new(name: SolidusMcp.configuration.server_name, version: VERSION,
        tools: tools, instructions: SolidusMcp.configuration.instructions)
    end
  end
end
