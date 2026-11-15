# frozen_string_literal: true

module SolidusMcp
  module Tools
    class SetVariantOptionValues < Base
      tool_name :set_variant_option_values
      description "Replace a non-master variant's complete option assignment. Supply exactly one value per product option type. Identical assignments are successful no-ops."
      category "Products"
      permission "set_variant_option_values"
      read_only false
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      ability :read, "Spree::OptionValue"
      ability :read, "Spree::OptionType"
      input :variant_id, type: "integer", minimum: 1, required: true
      input :option_value_ids, type: "array", items: {type: "integer", minimum: 1}, required: true

      protected

      def call(variant_id:, option_value_ids:)
        variant = policy.scope(Spree::Variant, :update)
          .where(product_id: policy.scope(Spree::Product, :update).select(:id)).find(variant_id)
        product = variant.product
        product.with_lock do
          variant.lock!
          authorize!
          raise ToolError, "Variant product changed; retrieve the variant again" unless variant.product_id == product.id
          policy.authorize_record!(:update, policy.scope(Spree::Product, :update).find(product.id))
          policy.scope(Spree::Variant, :update).find(variant.id)
          authorize_assignment!(variant)
          raise ToolError, "Master variants cannot have option values" if variant.is_master?
          raise ToolError, "Duplicate option value IDs" if option_value_ids.uniq != option_value_ids

          values = option_value_ids.map do |id|
            value = policy.authorize_record!(:read, policy.scope(Spree::OptionValue).find(id))
            policy.authorize_record!(:read, policy.scope(Spree::OptionType).find(value.option_type_id))
            value
          end
          types = values.map(&:option_type_id)
          unless types.uniq == types && types.sort == product.option_type_ids.sort
            raise ToolError, "Supply exactly one option value for each product option type"
          end
          previous = serializers.option_assignment(variant.option_values.reload)
          ids = option_value_ids.sort
          changed = variant.option_value_ids.sort != ids
          if changed
            # Check all active siblings, including those outside the caller's scope.
            # Only a generic conflict is exposed, never sibling IDs or labels.
            conflict = Spree::Variant.where(product_id: product.id, is_master: false, deleted_at: nil)
              .where.not(id: variant.id).includes(:option_values).any? { |sibling| sibling.option_value_ids.sort == ids }
            raise ToolError, "Option combination is unavailable" if conflict
            variant.option_values = values
            authorize_assignment!(variant)
            variant.save!
          end
          {variant_id: variant.id, product_id: product.id, changed: changed,
           previous_option_values: previous, option_values: serializers.option_assignment(variant.option_values.reload)}
        end
      end

      def authorize_assignment!(variant)
        policy.authorize_record!(:update, variant)
        %i[option_values option_value_ids].each do |attribute|
          policy.authorize_record!(:update, variant, attribute: attribute)
        end
      end
    end
  end
end
