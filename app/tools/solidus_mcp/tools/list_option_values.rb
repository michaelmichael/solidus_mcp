# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ListOptionValues < Base
      tool_name :list_option_values
      description "Discover authorized values for an option type before creating variants."
      category "Products"
      permission "list_option_values"
      read_only true
      ability :read, "Spree::OptionValue"
      ability :read, "Spree::OptionType"
      input :option_type_id, type: "integer", minimum: 1, required: true
      pagination

      protected

      def call(option_type_id:, after_id: 0, limit: 25)
        policy.authorize_record!(:read, policy.scope(Spree::OptionType).find(option_type_id))
        records = policy.scope(Spree::OptionValue).where(option_type_id: option_type_id)
        page(records, after_id: after_id, limit: limit) do |record|
          {id: record.id, name: record.name, presentation: record.presentation}
        end
      end
    end
  end
end
