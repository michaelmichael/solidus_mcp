# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ListOptionTypes < Base
      tool_name :list_option_types
      description "Discover option type IDs, names, and presentations, optionally filtered by name or product."
      category "Products"
      permission "list_option_types"
      read_only true
      ability :read, "Spree::OptionType"
      input :query, type: "string", minLength: 1, maxLength: 100
      input :product_id, type: "integer", minimum: 1
      pagination

      protected

      def call(query: nil, after_id: 0, limit: 25, product_id: nil)
        option_types = policy.scope(Spree::OptionType)
        if product_id
          product = policy.authorize_record!(:read, policy.scope(Spree::Product).find(product_id))
          option_types = option_types.where(id: product.option_types.select(:id))
        end
        if query
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          option_types = option_types.where("spree_option_types.name ILIKE :query OR spree_option_types.presentation ILIKE :query", query: pattern)
        end
        page(option_types, after_id: after_id, limit: limit) do |p|
          {id: p.id, name: p.name, presentation: p.presentation}
        end
      end
    end
  end
end
