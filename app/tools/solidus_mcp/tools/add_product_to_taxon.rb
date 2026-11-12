# frozen_string_literal: true

module SolidusMcp
  module Tools
    class AddProductToTaxon < Base
      tool_name :add_product_to_taxon
      description "Add a product to an existing taxon without replacing its other categories. New classifications append to the taxon's product ordering; repeated calls preserve existing positions."
      category "Products"
      permission "add_product_to_taxon"
      read_only false
      audit_action "create"
      ability :update, "Spree::Product"
      ability :read, "Spree::Taxon"
      ability :create, "Spree::Classification"
      input :product_id, type: "integer", minimum: 1, required: true
      input :taxon_id, type: "integer", minimum: 1, required: true

      protected

      def call(product_id:, taxon_id:)
        product = policy.scope(Spree::Product, :update).find(product_id)
        product.with_lock do
          taxon = policy.scope(Spree::Taxon).find(taxon_id)
          taxon.with_lock do
            authorize!
            policy.authorize_record!(:update, product)
            policy.authorize_record!(:update, product, attribute: :taxon_ids)
            policy.authorize_record!(:read, taxon)
            unless product.classifications.exists?(taxon_id: taxon.id)
              classification = product.classifications.build(taxon: taxon)
              policy.authorize_record!(:create, classification)
              classification.save!
            end
          end
        end
        {product_id: product.id, taxon_id: taxon_id, attached: true}
      end
    end
  end
end
