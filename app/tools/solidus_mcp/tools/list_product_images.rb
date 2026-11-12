# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ListProductImages < Base
      tool_name :list_product_images
      description "List authorized image metadata for a product master variant or explicit variant. ID pagination includes display positions but no storage URLs."
      category "Products"
      permission "list_product_images"
      read_only true
      ability :read, "Spree::Product"
      ability :read, "Spree::Variant"
      ability :read, "Spree::Image"
      input :product_id, type: "integer", minimum: 1, required: true
      input :variant_id, type: "integer", minimum: 1
      pagination

      protected

      def call(product_id:, variant_id: nil, after_id: 0, limit: 25)
        context = ImageContext.new(policy, product_id: product_id, variant_id: variant_id)
        page(context.images, after_id: after_id, limit: limit) { |image| context.metadata(image) }
      end
    end
  end
end
