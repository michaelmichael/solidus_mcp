# frozen_string_literal: true

module SolidusMcp
  class ImageContext
    attr_reader :product, :variant

    def initialize(policy, product_id:, variant_id: nil, action: :read)
      @policy, @action = policy, action
      @product = policy.scope(Spree::Product, action).find(product_id)
      id = variant_id || @product.master.id
      @variant = policy.scope(Spree::Variant, action).where(product_id: product_id).find(id)
      authorize!
    end

    def authorize!
      @policy.authorize_record!(@action, product)
      @policy.authorize_record!(@action, variant)
    end

    def with_lock
      product.with_lock do
        variant.with_lock do
          authorize!
          yield
        end
      end
    end

    def images(action = :read)
      @policy.scope(Spree::Image, action).where(viewable: variant)
    end

    def metadata(image)
      result = {id: image.id, product_id: product.id, variant_id: variant.id,
                position: image.position, alt: image.alt}
      if image.class.reflect_on_association(:attachment_attachment)
        blob = image.attachment.blob
        result[:content_type] = blob&.content_type
        result[:byte_size] = blob&.byte_size
      end
      result
    end
  end
end
