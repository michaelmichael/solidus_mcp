# frozen_string_literal: true

module SolidusMcp
  # A catalog of explicit tools, not business resources or arbitrary methods.
  class Registry
    Entry = Struct.new(:name, :description, :category, :permission, :read_only,
      :abilities, :input_schema, :class_name, keyword_init: true) do
      def scopes
        [read_only ? "mcp:read" : "mcp:write"]
      end

      def permissions
        [permission]
      end
    end

    attr_reader :tools

    def initialize
      @tools = {}
    end

    def register(klass)
      unless klass.is_a?(Class) && klass < SolidusMcp::Tool && klass.name.present?
        raise ArgumentError, "Expected a named SolidusMcp::Tool subclass"
      end
      unless klass.protected_instance_methods.include?(:call)
        raise ArgumentError, "Tool must implement a protected call method"
      end
      data = klass.registration
      name = data.fetch(:tool_name).to_s
      permission = data.fetch(:permission).to_s
      raise ArgumentError, "Invalid tool name" unless name.match?(/\A[a-z][a-z0-9_]*\z/)
      raise ArgumentError, "Invalid permission" unless permission.match?(/\A[a-z][a-z0-9_.]*\z/)
      raise ArgumentError, "Duplicate tool: #{name}" if tools.key?(name)
      raise ArgumentError, "Permission must be unique to this tool" if tools.values.any? { |tool| tool.permission == permission }
      raise ArgumentError, "read_only must be a boolean" unless [true, false].include?(data.fetch(:read_only))
      %i[description category].each { |key| raise ArgumentError, "Missing #{key}" if data.fetch(key).blank? }
      raise ArgumentError, "Tool needs Solidus abilities" if data[:abilities].empty?
      MCP::Tool::InputSchema.new(data[:input_schema])
      entry = Entry.new(name: name, permission: permission, **data.slice(:description, :category,
        :read_only, :abilities, :input_schema, :class_name))
      entry.each_pair { |_, value| deep_freeze(value) }
      tools[name] = entry.freeze
    end

    def permissions
      tools.values.map(&:permission)
    end

    def seal!
      tools.freeze
      freeze
    end

    private

    def deep_freeze(value)
      case value
      when Hash then value.each { |key, item|
        deep_freeze(key)
        deep_freeze(item)
      }
      when Array then value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
