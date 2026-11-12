# frozen_string_literal: true

module SolidusMcp
  module Tools
    class UpdateVariant < Base
      tool_name :update_variant
      description "Update variant SKU, weight, dimensions, cost price, or inventory tracking. Decimals are nonnegative strings with at most two decimal places. Changes take effect immediately."
      category "Products"
      permission "update_variant"
      read_only false
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      input :variant_id, type: "integer", minimum: 1, required: true
      input :changes, type: "object", minProperties: 1, additionalProperties: false, required: true,
        properties: {sku: {type: "string", minLength: 1, maxLength: 255},
                     weight: {type: "string", pattern: "^(0|[1-9][0-9]{0,5})(\\.[0-9]{1,2})?$", maxLength: 9},
                     height: {type: "string", pattern: "^(0|[1-9][0-9]{0,5})(\\.[0-9]{1,2})?$", maxLength: 9},
                     width: {type: "string", pattern: "^(0|[1-9][0-9]{0,5})(\\.[0-9]{1,2})?$", maxLength: 9},
                     depth: {type: "string", pattern: "^(0|[1-9][0-9]{0,5})(\\.[0-9]{1,2})?$", maxLength: 9},
                     cost_price: {type: "string", pattern: "^(0|[1-9][0-9]{0,7})(\\.[0-9]{1,2})?$", maxLength: 11},
                     track_inventory: {type: "boolean"}}

      protected

      def call(variant_id:, changes:)
        attributes = changes.symbolize_keys
        %i[weight height width depth cost_price].each do |attribute|
          next unless attributes.key?(attribute)
          digits = (attribute == :cost_price) ? 8 : 6
          unless attributes[attribute].match?(/\A(?:0|[1-9][0-9]{0,#{digits - 1}})(?:\.[0-9]{1,2})?\z/)
            raise ToolError, "#{attribute} must be a nonnegative decimal string with at most two decimal places"
          end
          attributes[attribute] = BigDecimal(attributes[attribute])
        end
        variant = policy.scope(Spree::Variant, :update)
          .where(product_id: policy.scope(Spree::Product, :update).select(:id)).find(variant_id)
        variant.with_lock do
          authorize!
          policy.authorize_record!(:update, variant.product)
          authorize_attributes!(variant, attributes)
          variant.assign_attributes(attributes)
          authorize_attributes!(variant, attributes)
          variant.save!
        end
        {variant_id: variant.id, updated: true}
      end

      def authorize_attributes!(variant, attributes)
        policy.authorize_record!(:update, variant)
        attributes.each_key { |attribute| policy.authorize_record!(:update, variant, attribute: attribute) }
      end
    end
  end
end
