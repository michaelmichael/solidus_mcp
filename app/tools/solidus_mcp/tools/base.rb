# frozen_string_literal: true

module SolidusMcp
  module Tools
    class Base < Tool
      class << self
        def pagination
          input :after_id, type: "integer", minimum: 0
          input :limit, type: "integer", minimum: 1, maximum: 100
        end
      end

      protected

      def serializers
        @serializers ||= Serializers.new(policy)
      end

      def page(relation, after_id:, limit:)
        table = relation.klass.arel_table
        records = relation.where(table[:id].gt(after_id)).reorder(table[:id].asc).limit(limit + 1).to_a
        more = records.length > limit
        records = records.first(limit)
        {items: records.map { |record| yield record }, next_after_id: more ? records.last.id : nil}
      end

      def variants
        policy.scope(Spree::Variant).where(product_id: policy.scope(Spree::Product).select(:id))
      end

      def stock_items
        policy.scope(Spree::StockItem).where(variant_id: variants.select(:id),
          stock_location_id: policy.scope(Spree::StockLocation).select(:id))
      end
    end
  end
end
