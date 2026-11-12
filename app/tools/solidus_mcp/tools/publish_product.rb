# frozen_string_literal: true

module SolidusMcp
  module Tools
    class PublishProduct < Base
      tool_name :publish_product
      description "Make a product available now without changing discontinuation or stock."
      category "Products"
      permission "publish_product"
      read_only false
      ability :update, "Spree::Product"
      input :product_id, type: "integer", minimum: 1, required: true

      protected

      def call(product_id:)
        product = policy.scope(Spree::Product, :update).find(product_id)
        product.with_lock do
          authorize!
          policy.authorize_record!(:update, product, attribute: :available_on)
          if product.discontinued?
            raise ToolError, "Discontinued products must be reinstated through the store before publishing"
          end
          product.available_on = Time.current unless product.available?
          policy.authorize_record!(:update, product, attribute: :available_on)
          product.save! if product.changed?
        end
        {product_id: product.id, available: !!product.available?}
      end
    end
  end
end
