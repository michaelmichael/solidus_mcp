# frozen_string_literal: true

module SolidusMcp
  module Tools
    class CreateProduct < Base
      tool_name :create_product
      description "Create a draft product."
      category "Products"
      permission "create_product"
      read_only false
      ability :create, "Spree::Product"
      input :name, type: "string", minLength: 1, maxLength: 255, required: true
      input :price, type: "number", minimum: 0, required: true
      input :shipping_category_id, type: "integer", minimum: 1

      protected

      def call(name:, price:, shipping_category_id: nil)
        default_shipping_category_id = SolidusMcp.configuration.default_shipping_category_id
        specified_shipping_category_id = shipping_category_id || default_shipping_category_id

        if specified_shipping_category_id.nil?
          raise SolidusMcp::ToolError, "Provide shipping_category_id. No default shipping category is configured."
        elsif Spree::ShippingCategory.find_by(id: specified_shipping_category_id).nil?
          raise SolidusMcp::ToolError, "The provided shipping category ID could not be found."
        end

        product = Spree::Product.new(
          name: name,
          price: price,
          shipping_category_id: specified_shipping_category_id
        )

        authorize!
        policy.authorize_record!(:create, product)
        product.save!

        {product_id: product.id, created: true}
      end
    end
  end
end
