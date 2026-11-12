# frozen_string_literal: true

require "base64"
require "digest"
require "stringio"

module SolidusMcp
  module Tools
    class AttachProductImage < Base
      tool_name :attach_product_image
      description "Upload a PNG, JPEG, GIF, or WebP image as base64 (at most 512 KiB decoded) to a product master or explicit variant. Requires an idempotency key. ActiveStorage only; no remote URLs."
      category "Products"
      permission "attach_product_image"
      read_only false
      audit_action "create"
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      ability :create, "Spree::Image"
      input :product_id, type: "integer", minimum: 1, required: true
      input :variant_id, type: "integer", minimum: 1
      input :filename, type: "string", minLength: 1, maxLength: 128, required: true
      input :content_type, type: "string", enum: %w[image/png image/jpeg image/gif image/webp], required: true
      input :data_base64, type: "string", minLength: 1, maxLength: 699052, required: true
      input :alt, type: "string", maxLength: 1000
      input :idempotency_key, type: "string", minLength: 1, maxLength: 128, required: true

      protected

      def call(product_id:, filename:, content_type:, data_base64:, idempotency_key:, variant_id: nil, alt: "")
        unless Spree::Image.reflect_on_association(:attachment_attachment)
          raise ToolError, "This upload tool requires the standard ActiveStorage image adapter"
        end
        if filename.match?(/[\\\/\x00-\x1f]/) || filename.strip.empty?
          raise ToolError, "Filename must be a plain file name"
        end
        begin
          data = Base64.strict_decode64(data_base64)
        rescue ArgumentError
          raise ToolError, "Invalid base64 image"
        end
        unless data.bytesize.between?(1, 524288) && Marcel::MimeType.for(StringIO.new(data)) == content_type
          raise ToolError, "Image content or size does not match the upload constraints"
        end
        context = ImageContext.new(policy, product_id: product_id, variant_id: variant_id, action: :update)
        request = ToolRequestExecution.new(credential, operation: "attach_product_image", key: idempotency_key,
          payload: {product_id: product_id, variant_id: context.variant.id, filename: filename,
                    content_type: content_type, digest: Digest::SHA256.hexdigest(data), alt: alt})
        blob = nil
        context.with_lock do
          authorize!
          image = Spree::Image.new(viewable: context.variant, alt: alt)
          policy.authorize_record!(:create, image)
          request.database do
            io = StringIO.new(data)
            blob = ActiveStorage::Blob.build_after_unfurling(io: io, filename: filename, content_type: content_type, identify: false)
            blob.save!
            blob.upload_without_unfurling(io)
            image.attachment = blob
            policy.authorize_record!(:create, image)
            image.save!
            context.metadata(image)
          end
        end
      rescue
        begin
          if blob && !ActiveStorage::Attachment.exists?(blob_id: blob.id)
            blob.service.delete(blob.key)
            blob.destroy! if blob.persisted?
          end
        rescue
          Rails.logger.warn("Solidus MCP image upload cleanup failed; inspect unattached blobs")
        end
        raise
      end
    end
  end
end
