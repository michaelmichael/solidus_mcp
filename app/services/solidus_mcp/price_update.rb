# frozen_string_literal: true

module SolidusMcp
  # Shared only by the two pricing tools. Updates an exact existing context;
  # it never guesses a price, creates a row, or bypasses Solidus validations.
  class PriceUpdate
    def initialize(policy)
      @policy = policy
    end

    def call(variant_id:, currency:, country_iso:, amount:)
      valid_context = currency.match?(/\A[A-Z]{3}\z/) && (country_iso.nil? || country_iso.match?(/\A[A-Z]{2}\z/))
      raise ToolError, "Invalid currency or country context" unless valid_context
      unless amount.is_a?(String) && amount.match?(/\A(?:0|[1-9]\d{0,7})(?:\.\d{1,2})?\z/)
        raise ToolError, "Amount must be a nonnegative decimal string with at most two decimal places"
      end
      unless Spree::Config.pricing_options_class == Spree::Variant::PricingOptions
        raise ToolError, "Custom pricing options require a store-specific pricing tool"
      end
      variant = @policy.scope(Spree::Variant, :update)
        .where(product_id: @policy.scope(Spree::Product, :update).select(:id)).find(variant_id)
      prices = @policy.scope(Spree::Price, :update).where(variant_id: variant.id,
        currency: currency, country_iso: country_iso).limit(2).to_a
      raise ToolError, "Price context is unavailable or ambiguous" unless prices.one?
      price = prices.first
      price.with_lock do
        yield
        @policy.authorize_record!(:update, variant.product)
        @policy.authorize_record!(:update, variant)
        @policy.authorize_record!(:update, price)
        unless price.variant_id == variant_id && price.currency == currency && price.country_iso == country_iso
          raise ToolError, "Price context changed; retrieve prices again"
        end
        price.assign_attributes(amount: BigDecimal(amount))
        @policy.authorize_record!(:update, price)
        price.save!
      end
      {price_id: price.id, variant_id: variant.id, currency: price.currency,
       country_iso: price.country_iso, amount: price.amount.to_s("F")}
    end
  end
end
