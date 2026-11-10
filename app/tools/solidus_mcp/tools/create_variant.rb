# frozen_string_literal: true

module SolidusMcp
  module Tools
    class CreateVariant < Base
      tool_name :create_variant
      description "Create a non-master variant for an existing product using existing option values. Price defaults to the master price; stock items follow Solidus callbacks."
      category "Products"
      permission "create_variant"
      read_only false
      ability :update, "Spree::Product"
      ability :create, "Spree::Variant"

      input :product_id, type: "integer", minimum: 1, required: true
      input :sku, type: "string", minLength: 1, maxLength: 255, required: true
      input :price, type: "number", minimum: 0
      input :option_value_ids, type: "array", items: {type: "integer", minimum: 1}, uniqueItems: true
      input :track_inventory, type: "boolean"
      %i[weight height width depth cost_price].each do |attribute|
        input attribute, type: "number", minimum: 0
      end

      protected

      def call(product_id:, sku:, option_value_ids: [], **attributes)
        product = policy.scope(Spree::Product, :update).find(product_id)
        policy.authorize_record!(:update, product)

        Spree::Variant.transaction do
          option_values = policy.scope(Spree::OptionValue).where(id: option_value_ids).to_a
          unless option_values.map(&:id).sort == option_value_ids.sort
            raise SolidusMcp::ToolError, "One or more option values are unavailable."
          end
          option_type_ids = option_values.map(&:option_type_id)
          unless option_type_ids.uniq.size == option_type_ids.size
            raise SolidusMcp::ToolError, "Provide at most one value for each option type."
          end
          unless (option_type_ids - product.option_type_ids).empty?
            raise SolidusMcp::ToolError, "Option values must belong to the product's option types."
          end

          variant = product.variants.build(attributes.merge(sku: sku, is_master: false))
          variant.option_values = option_values
          authorize!
          policy.authorize_record!(:create, variant)
          variant.save!

          {variant_id: variant.id, product_id: product.id, sku: variant.sku, created: true}
        end
      end
    end
  end
end
