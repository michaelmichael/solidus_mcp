# frozen_string_literal: true

module SolidusMcp
  # Metadata and implementation live together. Invoke through .execute; #call is
  # deliberately protected so direct Ruby callers use the same checks as MCP.
  class Tool
    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@declaration, declaration.deep_dup)
      end

      %i[tool_name description category permission read_only].each do |key|
        define_method(key) { |value| declaration[key] = value }
      end

      def ability(action, model)
        declaration[:abilities] << [action.to_sym, model.to_s]
      end

      def input(name, required: false, **schema)
        key = name.to_s
        raise ArgumentError, "Duplicate input: #{key}" if declaration[:properties].key?(key)
        declaration[:properties][key] = schema
        declaration[:required] << key if required
      end

      def registration
        declaration.deep_dup.merge(class_name: name,
          input_schema: {type: "object", properties: declaration[:properties],
                         required: declaration[:required], additionalProperties: false})
      end

      def execute(credential:, **arguments)
        entry = SolidusMcp.registry.tools[registration.fetch(:tool_name).to_s]
        raise AccessDenied, "Unregistered tool" unless entry && entry.class_name == name
        policy = Policy.new(credential)
        policy.authorize!(entry)
        MCP::Tool::InputSchema.new(entry.input_schema).validate_arguments(arguments)
        new(credential, policy).send(:call, **arguments)
      end

      private

      def declaration
        @declaration ||= {properties: {}, required: [], abilities: []}
      end
    end

    attr_reader :credential, :policy

    def initialize(credential, policy)
      @credential = credential
      @policy = policy
    end

    protected

    def authorize!
      policy.authorize!(SolidusMcp.registry.tools.fetch(self.class.registration.fetch(:tool_name).to_s))
    end
  end
end
