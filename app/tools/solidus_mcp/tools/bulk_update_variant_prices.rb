# frozen_string_literal: true

module SolidusMcp
  module Tools
    class BulkUpdateVariantPrices < Base
      tool_name :bulk_update_variant_prices
      description "Update up to 100 SKU prices independently. Each entry specifies amount, currency and country_iso (null for general-country pricing). Returns a result for every entry."
      category "Pricing"
      permission "bulk_update_variant_prices"
      read_only false
      ability :update, "Spree::Product"
      ability :update, "Spree::Variant"
      ability :update, "Spree::Price"
      input :entries, type: "array", minItems: 1, maxItems: 100, required: true,
        items: {type: "object", additionalProperties: false,
                required: %w[sku amount currency country_iso],
                properties: {sku: {type: "string", minLength: 1, maxLength: 255},
                             amount: {type: "string"}, currency: {type: "string"},
                             country_iso: {type: ["string", "null"]}}}

      protected

      def call(entries:)
        entries = entries.map(&:stringify_keys)
        keys = entries.map { |entry| entry.values_at("sku", "currency", "country_iso") }
        duplicates = keys.tally.select { |_, count| count > 1 }.keys
        results = entries.each_with_index.map do |entry, index|
          authorize!
          raise ToolError, "Duplicate pricing target" if duplicates.include?(keys[index])
          candidates = policy.scope(Spree::Variant, :update).where(sku: entry.fetch("sku")).limit(2).to_a
          raise ToolError, "SKU is unavailable or ambiguous" unless candidates.one?
          result = PriceUpdate.new(policy).call(variant_id: candidates.first.id,
            **entry.except("sku").symbolize_keys) { authorize! }
          {index: index, sku: entry["sku"], success: true, price: result}
        rescue AccessDenied, ToolError => e
          {index: index, sku: entry["sku"], success: false, error: e.message}
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
          {index: index, sku: entry["sku"], success: false, error: "Concurrent price change; retry this entry"}
        rescue ActiveRecord::RecordNotFound
          {index: index, sku: entry["sku"], success: false, error: "Price is unavailable"}
        rescue ActiveRecord::RecordInvalid => e
          {index: index, sku: entry["sku"], success: false, error: e.record.errors.full_messages.to_sentence}
        end
        {results: results}
      end
    end
  end
end
