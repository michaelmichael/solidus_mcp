# frozen_string_literal: true

module SolidusMcp
  # Server-owned declarations only. Clients cannot resolve model or method names.
  # A resource is a permission group; it is not an MCP protocol resource URI.
  class Registry
    Permission = Struct.new(:key, :resource, :action, :model_name, :ability_action, keyword_init: true)
    Resource = Struct.new(:key, :label, :model_name, :permissions, keyword_init: true)
    Tool = Struct.new(:name, :resource, :permissions, :scopes, :description, :input_schema,
      :read_only, :handler_name, keyword_init: true)

    attr_reader :resources, :permissions, :tools

    def initialize
      @resources = {}
      @permissions = {}
      @tools = {}
    end

    def resource(key, model:, label:, actions:)
      key = identifier!(key)
      raise ArgumentError, "Duplicate resource: #{key}" if resources.key?(key)
      raise ArgumentError, "Model must be a class name" unless model.is_a?(String) && !model.empty?
      raise ArgumentError, "Resource needs actions" if actions.empty?
      model = model.dup.freeze

      entries = actions.map do |action, ability_action|
        action = identifier!(action)
        permission = Permission.new(key: "#{key}.#{action}".freeze, resource: key, action: action,
          model_name: model, ability_action: ability_action.to_sym).freeze
        permissions[permission.key] = permission
      end
      resources[key] = Resource.new(key: key, label: label.to_s.dup.freeze, model_name: model, permissions: entries.freeze).freeze
    end

    def tool(name, resource:, permissions:, definition:, handler:)
      name = identifier!(name)
      raise ArgumentError, "Reserved tool name: #{name}" if %w[list_capabilities describe_resource].include?(name)
      raise ArgumentError, "Duplicate tool: #{name}" if tools.key?(name)
      resource = resource.to_s
      raise ArgumentError, "Unknown resource: #{resource}" unless resources.key?(resource)
      keys = Array(permissions).map { |key| key.to_s.dup.freeze }
      raise ArgumentError, "Tool needs permissions" if keys.empty?
      keys.each { |key| self.permissions.fetch(key) { raise ArgumentError, "Unknown permission: #{key}" } }
      scopes = Array(definition.fetch(:scope)).map { |scope| scope.to_s.dup.freeze }
      raise ArgumentError, "Tool needs OAuth scopes" if scopes.empty?
      raise ArgumentError, "read_only must be a boolean" unless [true, false].include?(definition.fetch(:read_only))
      raise ArgumentError, "Handler must be a class name" unless handler.is_a?(String) && !handler.empty?

      tools[name] = Tool.new(name: name, resource: resource, permissions: keys.freeze, scopes: scopes.freeze,
        description: definition.fetch(:description).dup.freeze,
        input_schema: deep_freeze(type: "object", properties: definition.fetch(:properties).deep_dup,
          required: definition.fetch(:required).dup, additionalProperties: false),
        read_only: definition.fetch(:read_only), handler_name: handler.dup.freeze).freeze
    end

    def seal!
      resources.freeze
      permissions.freeze
      tools.freeze
      freeze
    end

    private

    def identifier!(value)
      value = value.to_s
      raise ArgumentError, "Invalid registry identifier" unless value.match?(/\A[a-z][a-z0-9_]*\z/)
      value.freeze
    end

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
