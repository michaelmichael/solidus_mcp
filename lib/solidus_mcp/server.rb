# frozen_string_literal: true

module SolidusMcp
  class Server
    def self.build(credential:, name:, version:, instructions:, errors: [])
      registry = SolidusMcp.registry
      policy = Policy.new(credential, registry: registry)
      tools = registry.tools.values.filter_map do |tool|
        next unless policy.allowed?(tool)

        MCP::Tool.define(name: tool.name, description: tool.description, input_schema: tool.input_schema,
          annotations: {read_only_hint: tool.read_only, destructive_hint: !tool.read_only,
                        idempotent_hint: tool.read_only, open_world_hint: false}) do |**arguments|
          arguments.delete(:server_context)
          policy.authorize!(tool)
          result = tool.handler_name.constantize.new(credential).public_send(tool.name, **arguments)
          SolidusMcp::Server.response(result)
        rescue AccessDenied, *errors => e
          MCP::Tool::Response.new([{type: "text", text: e.message}], error: true)
        end
      end

      tools << MCP::Tool.define(name: "list_capabilities",
        description: "List the registered store resources and operations this connection may use.",
        input_schema: {type: "object", properties: {}, additionalProperties: false},
        annotations: {read_only_hint: true, destructive_hint: false, open_world_hint: false}) do |**|
        SolidusMcp::Server.response(resources: SolidusMcp::Server.capabilities(registry, policy))
      end
      tools << MCP::Tool.define(name: "describe_resource",
        description: "Describe allowed tools and exact input schemas for one resource from list_capabilities.",
        input_schema: {type: "object", properties: {resource: {type: "string"}}, required: ["resource"], additionalProperties: false},
        annotations: {read_only_hint: true, destructive_hint: false, open_world_hint: false}) do |resource:, **|
        data = SolidusMcp::Server.capabilities(registry, policy, schemas: true).find { |entry| entry[:resource] == resource }
        if data
          SolidusMcp::Server.response(data)
        else
          MCP::Tool::Response.new([{type: "text", text: "Resource is unavailable to this connection"}], error: true)
        end
      end
      MCP::Server.new(name: name, version: version, tools: tools, instructions: instructions)
    end

    def self.response(result)
      MCP::Tool::Response.new([{type: "text", text: result.to_json}], structured_content: result)
    end

    def self.capabilities(registry, policy, schemas: false)
      allowed = registry.tools.values.select { |tool| policy.allowed?(tool) }
      registry.resources.values.filter_map do |resource|
        tools = allowed.select { |tool| tool.resource == resource.key }
        next if tools.empty?
        {resource: resource.key, label: resource.label, operations: tools.map do |tool|
          data = {name: tool.name, description: tool.description, permissions: tool.permissions,
                  scopes: tool.scopes, read_only: tool.read_only}
          data[:input_schema] = tool.input_schema if schemas
          data
        end}
      end
    end
  end
end
