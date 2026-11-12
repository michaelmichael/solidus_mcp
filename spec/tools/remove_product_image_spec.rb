# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::RemoveProductImage do
  include_context "image tools"
  include_examples "a dedicated pending tool", "remove_product_image", -> { {product_id: product.id, image_id: 1} }

  it "destroys the image and attachment through model callbacks; repeats fail safely" do
    id = upload_image[:id]
    execute("remove_product_image", product_id: product.id, image_id: id)
    expect(Spree::Image.exists?(id)).to be(false)
    expect(ActiveStorage::Attachment.where(record_type: "Spree::Asset", record_id: id)).to be_empty
    expect { execute("remove_product_image", product_id: product.id, image_id: id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "rejects foreign parent context and unauthorized deletion" do
    id = upload_image[:id]
    other = create_product(sku: "OTHER")
    expect { execute("remove_product_image", product_id: other.id, image_id: id) }.to raise_error(ActiveRecord::RecordNotFound)
    restrict { |ability| ability.cannot :destroy, Spree::Image, id: id }
    expect { execute("remove_product_image", product_id: product.id, image_id: id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Spree::Image.exists?(id)).to be(true)
  end
end
