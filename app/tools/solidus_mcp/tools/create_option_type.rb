# frozen_string_literal: true

module SolidusMcp
  module Tools
    class CreateOptionType < Base
      tool_name :create_option_type
      description "Create an option type with an internal name and display presentation. Names must be unique. Does not attach the type to products."
      category "Products"
      permission "create_option_type"
      read_only false
      audit_action "create"
      ability :create, "Spree::OptionType"
      input :name, type: "string", minLength: 1, maxLength: 255, required: true
      input :presentation, type: "string", minLength: 1, maxLength: 255, required: true

      protected

      def call(name:, presentation:)
        option_type = Spree::OptionType.new(name: name, presentation: presentation)
        authorize!
        policy.authorize_record!(:create, option_type)
        option_type.save!
        {option_type_id: option_type.id, name: option_type.name,
         presentation: option_type.presentation, created: true}
      end
    end
  end
end
