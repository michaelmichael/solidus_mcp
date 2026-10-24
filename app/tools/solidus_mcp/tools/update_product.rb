# frozen_string_literal: true

module SolidusMcp
  module Tools
    class UpdateProduct < Base
      tool_name :update_product
      description "Update explicitly supported product attributes using Solidus validation. Changes take effect immediately."
      category "Products"
      permission "update_product"
      read_only false
      ability :update, "Spree::Product"
      input :product_id, type: "integer", minimum: 1, required: true
      input :changes, type: "object", minProperties: 1, additionalProperties: false, required: true,
        properties: {name: {type: "string", minLength: 1, maxLength: 255},
                     description: {type: "string", maxLength: 50000},
                     meta_title: {type: "string", maxLength: 255},
                     meta_description: {type: "string", maxLength: 1000},
                     meta_keywords: {type: "string", maxLength: 1000}}

      protected

      def call(product_id:, changes:)
        product = policy.scope(Spree::Product, :update).find(product_id)
        product.with_lock do
          authorize!
          policy.authorize_record!(:update, product)
          product.assign_attributes(changes)
          policy.authorize_record!(:update, product)
          product.save!
        end
        {product_id: product.id, updated: true}
      end
    end
  end
end
