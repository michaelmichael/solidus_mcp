# frozen_string_literal: true

module SolidusMcp
  module Tools
    class RemoveProductImage < Base
      tool_name :remove_product_image
      description "Permanently remove one image from an explicit product/variant parent. Missing or already removed IDs fail safely; attachment cleanup follows Solidus and ActiveStorage callbacks."
      category "Products"
      permission "remove_product_image"
      read_only false
      audit_action "delete"
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      ability :destroy, "Spree::Image"
      input :product_id, type: "integer", minimum: 1, required: true
      input :variant_id, type: "integer", minimum: 1
      input :image_id, type: "integer", minimum: 1, required: true

      protected

      def call(product_id:, image_id:, variant_id: nil)
        context = ImageContext.new(policy, product_id: product_id, variant_id: variant_id, action: :update)
        context.with_lock do
          authorize!
          image = context.images(:destroy).find(image_id)
          policy.authorize_record!(:destroy, image)
          image.destroy!
        end
        {image_id: image_id, removed: true}
      end
    end
  end
end
