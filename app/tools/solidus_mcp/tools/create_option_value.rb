# frozen_string_literal: true

module SolidusMcp
  module Tools
    class CreateOptionValue < Base
      tool_name :create_option_value
      description "Create an option value belonging to an existing authorized option type. Names must be unique within the type. Does not assign the value to variants."
      category "Products"
      permission "create_option_value"
      read_only false
      audit_action "create"
      ability :read, "Spree::OptionType"
      ability :create, "Spree::OptionValue"
      input :option_type_id, type: "integer", minimum: 1, required: true
      input :name, type: "string", minLength: 1, maxLength: 255, required: true
      input :presentation, type: "string", minLength: 1, maxLength: 255, required: true

      protected

      def call(option_type_id:, name:, presentation:)
        option_type = policy.scope(Spree::OptionType).find(option_type_id)
        option_type.with_lock do
          authorize!
          policy.authorize_record!(:read, policy.scope(Spree::OptionType).find(option_type.id))
          value = Spree::OptionValue.new(option_type: option_type, name: name, presentation: presentation)
          policy.authorize_record!(:create, value)
          value.save!
          {option_value_id: value.id, option_type_id: option_type.id, name: value.name,
           presentation: value.presentation, option_type_name: option_type.name,
           option_type_presentation: option_type.presentation, created: true}
        end
      end
    end
  end
end
