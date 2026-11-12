# frozen_string_literal: true

module SolidusMcp
  module Tools
    class AddProductOptionType < Base
      tool_name :add_product_option_type
      description "Attach an existing option type to a product, preserving existing options and variants. Repeated calls are safe."
      category "Products"
      permission "add_product_option_type"
      read_only false
      audit_action "create"
      ability :update, "Spree::Product"
      ability :read, "Spree::OptionType"
      ability :create, "Spree::ProductOptionType"
      input :product_id, type: "integer", minimum: 1, required: true
      input :option_type_id, type: "integer", minimum: 1, required: true

      protected

      def call(product_id:, option_type_id:)
        product = policy.scope(Spree::Product, :update).find(product_id)
        product.with_lock do
          authorize!
          policy.authorize_record!(:update, product)
          option_type = policy.authorize_record!(:read, policy.scope(Spree::OptionType).find(option_type_id))
          unless product.product_option_types.exists?(option_type_id: option_type.id)
            attachment = product.product_option_types.build(option_type: option_type)
            policy.authorize_record!(:create, attachment)
            attachment.save!
          end
        end
        {product_id: product.id, option_type_id: option_type_id, attached: true}
      end
    end
  end
end
