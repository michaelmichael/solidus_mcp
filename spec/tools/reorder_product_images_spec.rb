# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::ReorderProductImages do
  include_context "image tools"
  include_examples "a dedicated pending tool", "reorder_product_images", -> { {product_id: product.id, image_ids: []} }

  it "atomically replaces complete ordering and can be repeated" do
    ids = [upload_image[:id], upload_image(idempotency_key: "image-2")[:id]]
    2.times { execute("reorder_product_images", product_id: product.id, image_ids: ids.reverse) }
    expect(product.master.images.reload.pluck(:id)).to eq(ids.reverse)
    expect(product.master.images.pluck(:position)).to eq([1, 2])
  end

  it "rejects partial, foreign, and duplicate image IDs" do
    ids = [upload_image[:id], upload_image(idempotency_key: "image-2")[:id]]
    expect { execute("reorder_product_images", product_id: product.id, image_ids: [ids.first]) }.to raise_error(SolidusMcp::ToolError)
    expect { execute("reorder_product_images", product_id: product.id, image_ids: [ids.first, ids.last + 1]) }.to raise_error(SolidusMcp::ToolError)
    expect { execute("reorder_product_images", product_id: product.id, image_ids: [ids.first, ids.first]) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect(product.master.images.reload.pluck(:id)).to eq(ids)
  end

  it "rejects unauthorized positions before changing any image" do
    ids = [upload_image[:id], upload_image(idempotency_key: "image-2")[:id]]
    restrict { |ability| ability.cannot :update, Spree::Image, :position, id: ids.last }
    expect { execute("reorder_product_images", product_id: product.id, image_ids: ids.reverse) }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.master.images.reload.pluck(:id)).to eq(ids)
  end
  it "rolls back ordering when the final position violates record conditions" do
    ids = [upload_image[:id], upload_image(idempotency_key: "image-2")[:id]]
    restrict { |ability| ability.cannot :update, Spree::Image, :position, id: ids.last, position: 1 }
    expect { execute("reorder_product_images", product_id: product.id, image_ids: ids.reverse) }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.master.images.reload.pluck(:id)).to eq(ids)
  end
end
