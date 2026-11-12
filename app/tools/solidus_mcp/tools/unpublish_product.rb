# frozen_string_literal: true

module SolidusMcp
  module Tools
    class UnpublishProduct < Base
      tool_name :unpublish_product
      description "Withdraw product availability without deleting it, its variants, or order history."
      category "Products"
      permission "unpublish_product"
      read_only false
      ability :update, "Spree::Product"
      input :product_id, type: "integer", minimum: 1, required: true

      protected

      def call(product_id:)
        product = policy.scope(Spree::Product, :update).find(product_id)
        product.with_lock do
          authorize!
          policy.authorize_record!(:update, product, attribute: :available_on)
          product.available_on = nil
          policy.authorize_record!(:update, product, attribute: :available_on)
          product.save! if product.changed?
        end
        {product_id: product.id, available: !!product.available?}
      end
    end
  end
end
