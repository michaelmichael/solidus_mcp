# frozen_string_literal: true

module SolidusMcp
  module Tools
    class CreateOptionValue < Base
      tool_name :create_option_value
      description "Create an option value under an existing option type. Returns an ID usable with create_variant; does not attach the option type to a product."
      category "Products"
      permission "create_option_value"
      read_only false
      ability :update, "Spree::OptionType"
      ability :create, "Spree::OptionValue"

      input :option_type_id, type: "integer", minimum: 1, required: true
      input :name, type: "string", minLength: 1, maxLength: 255, required: true
      input :presentation, type: "string", minLength: 1, maxLength: 255, required: true

      protected

      def call(option_type_id:, name:, presentation:)
        option_type = policy.scope(Spree::OptionType, :update).find(option_type_id)
        policy.authorize_record!(:update, option_type)
        option_value = option_type.option_values.build(name: name, presentation: presentation)
        authorize!
        policy.authorize_record!(:create, option_value)
        option_value.save!

        {option_value_id: option_value.id, option_type_id: option_type.id,
         name: option_value.name, presentation: option_value.presentation, created: true}
      end
    end
  end
end
