# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ReorderProductImages < Base
      tool_name :reorder_product_images
      description "Replace the complete image ordering for one product master or explicit variant. All image IDs must be supplied exactly once; changes are atomic."
      category "Products"
      permission "reorder_product_images"
      read_only false
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      ability :update, "Spree::Image"
      input :product_id, type: "integer", minimum: 1, required: true
      input :variant_id, type: "integer", minimum: 1
      input :image_ids, type: "array", items: {type: "integer", minimum: 1}, uniqueItems: true, maxItems: 100, required: true

      protected

      def call(product_id:, image_ids:, variant_id: nil)
        context = ImageContext.new(policy, product_id: product_id, variant_id: variant_id, action: :update)
        context.with_lock do
          authorize!
          # Check the complete parent collection, not just its readable subset.
          actual = Spree::Image.where(viewable: context.variant).limit(101).pluck(:id)
          unless actual.sort == image_ids.sort
            raise ToolError, "Supply every image in this parent exactly once"
          end
          images = context.images(:update).where(id: image_ids).index_by(&:id)
          raise AccessDenied, "Record is unavailable" unless images.length == actual.length
          image_ids.each do |id|
            policy.authorize_record!(:update, images.fetch(id), attribute: :position)
          end
          image_ids.each_with_index { |id, index| images.fetch(id).insert_at(index + 1) }
          images.each_value { |image| policy.authorize_record!(:update, image.reload, attribute: :position) }
        end
        {product_id: product_id, variant_id: context.variant.id, image_ids: image_ids}
      end
    end
  end
end
