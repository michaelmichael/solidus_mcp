# frozen_string_literal: true

module SolidusMcp
  module Tools
    class CreateVariantPrice < Base
      tool_name :create_variant_price
      description "Create a variant price in an explicit currency/country context. Identical retries return the existing row; conflicting or ambiguous contexts fail. Standard Solidus pricing options only."
      category "Pricing"
      permission "create_variant_price"
      read_only false
      audit_action "create"
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      ability :create, "Spree::Price"
      input :variant_id, type: "integer", minimum: 1, required: true
      input :currency, type: "string", pattern: "^[A-Z]{3}$", required: true
      input :country_iso, anyOf: [{type: "string", pattern: "^[A-Z]{2}$"}, {type: "null"}], required: true
      input :amount, type: "string", required: true

      protected

      def call(variant_id:, currency:, country_iso:, amount:)
        unless amount.match?(/\A(?:0|[1-9][0-9]{0,7})(?:\.[0-9]{1,2})?\z/)
          raise ToolError, "Amount must be a nonnegative decimal string with at most two decimal places"
        end
        valid_context = currency.match?(/\A[A-Z]{3}\z/) && (country_iso.nil? || country_iso.match?(/\A[A-Z]{2}\z/))
        unless valid_context
          raise ToolError, "Invalid currency or country context"
        end
        unless Spree::Config.pricing_options_class == Spree::Variant::PricingOptions
          raise ToolError, "Custom pricing options require a store-specific pricing tool"
        end
        variant = policy.scope(Spree::Variant, :update)
          .where(product_id: policy.scope(Spree::Product, :update).select(:id)).find(variant_id)
        variant.with_lock do
          authorize!
          policy.authorize_record!(:update, variant.product)
          policy.authorize_record!(:update, variant)
          price = Spree::Price.new(variant: variant, currency: currency, country_iso: country_iso, amount: BigDecimal(amount))
          policy.authorize_record!(:create, price)
          # Inspect every active row, including rows hidden by price read scope:
          # never create a second context because an existing row is unreadable.
          existing = Spree::Price.where(variant_id: variant.id, currency: currency, country_iso: country_iso).limit(2).to_a
          if existing.any?
            unless existing.one? && existing.first.amount == price.amount
              raise ToolError, "Price context already exists or is ambiguous; use an update tool"
            end
            policy.authorize_record!(:read, existing.first)
            price = existing.first
          else
            price.save!
          end
          {price_id: price.id, variant_id: variant.id, currency: price.currency,
           country_iso: price.country_iso, amount: price.amount.to_s("F")}
        end
      end
    end
  end
end
