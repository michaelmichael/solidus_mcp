# frozen_string_literal: true

module SolidusMcp
  module Tools
    class ListTaxons < Base
      tool_name :list_taxons
      description "Browse authorized taxon IDs, names, parent IDs, taxonomy IDs, and depth. Optional literal name search, taxonomy filter, or direct-parent filter; parent_id null selects roots. Results use ID cursor pagination, not tree order."
      category "Products"
      permission "list_taxons"
      read_only true
      ability :read, "Spree::Taxon"
      input :query, type: "string", minLength: 1, maxLength: 100
      input :taxonomy_id, type: "integer", minimum: 1
      input :parent_id, anyOf: [{type: "integer", minimum: 1}, {type: "null"}]
      pagination

      protected

      def call(query: nil, taxonomy_id: nil, parent_id: :all, after_id: 0, limit: 25)
        taxons = policy.scope(Spree::Taxon)
        if taxonomy_id
          policy.authorize_record!(:read, policy.scope(Spree::Taxonomy).find(taxonomy_id))
          taxons = taxons.where(taxonomy_id: taxonomy_id)
        end
        unless parent_id == :all
          policy.authorize_record!(:read, policy.scope(Spree::Taxon).find(parent_id)) if parent_id
          taxons = taxons.where(parent_id: parent_id)
        end
        if query
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          taxons = taxons.where("spree_taxons.name ILIKE ?", pattern)
        end
        page(taxons, after_id: after_id, limit: limit) do |taxon|
          {id: taxon.id, name: taxon.name, parent_id: taxon.parent_id,
           taxonomy_id: taxon.taxonomy_id, depth: taxon.depth}
        end
      end
    end
  end
end
