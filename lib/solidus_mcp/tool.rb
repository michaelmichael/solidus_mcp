# frozen_string_literal: true

module SolidusMcp
  # A server-owned tool declaration and request-local implementation. The registry
  # stores the class name, never the class object, so Rails can reload tool files.
  class Tool
    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@declaration, declaration.deep_dup)
      end

      %i[tool_name description resource read_only].each do |key|
        define_method(key) do |value|
          declaration[key] = value
        end
      end

      def permissions(*keys)
        declaration[:permissions] = keys.flatten
      end

      def scope(*scopes)
        declaration[:scope] = scopes.flatten
      end

      def input(name, required: false, **schema)
        key = name.to_s
        raise ArgumentError, "Duplicate input: #{key}" if declaration[:properties].key?(key)
        declaration[:properties][key] = schema
        declaration[:required] << key if required
      end

      def registration
        {
          name: declaration.fetch(:tool_name), resource: declaration.fetch(:resource),
          permissions: declaration.fetch(:permissions), handler: name, handler_method: :call,
          definition: declaration.slice(:scope, :description, :read_only, :properties, :required)
        }
      end

      private

      def declaration
        @declaration ||= {properties: {}, required: []}
      end
    end

    attr_reader :credential, :policy

    def initialize(credential)
      @credential = credential
      @policy = Policy.new(credential)
    end

    # Use at the service entry point too when calling a tool outside the server.
    def authorize!
      tool = SolidusMcp.registry.tools[self.class.registration.fetch(:name).to_s]
      raise AccessDenied, "Tool is not registered to this handler" unless tool&.handler_name == self.class.name && tool.handler_method == "call"
      policy.authorize!(tool)
    end
  end
end
