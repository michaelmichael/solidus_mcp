# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::ListProductImages do
  include_context "image tools"
  include_examples "a dedicated pending tool", "list_product_images", -> { {product_id: product.id} }

  it "returns paginated metadata without storage paths or credentials" do
    first = upload_image
    second = upload_image(idempotency_key: "image-2")
    result = execute("list_product_images", product_id: product.id, limit: 1)
    expect(result[:items].first).to eq(first)
    expect(result[:items].first.keys).to match_array(%i[id product_id variant_id position alt content_type byte_size])
    expect(result[:next_after_id]).to eq(first[:id])
    last = execute("list_product_images", product_id: product.id, limit: 1, after_id: result[:next_after_id])
    expect(last[:items].pluck(:id)).to eq([second[:id]])
    expect(last[:next_after_id]).to be_nil
  end

  it "uses explicit variant ownership and scopes images and parents" do
    child = Spree::Variant.create!(product: product, sku: "CHILD", price: "12.50")
    image = upload_image(variant_id: child.id)
    expect(execute("list_product_images", product_id: product.id)[:items]).to be_empty
    expect(execute("list_product_images", product_id: product.id, variant_id: child.id)[:items].pluck(:id)).to eq([image[:id]])
    restrict { |ability| ability.cannot :read, Spree::Image, id: image[:id] }
    expect(execute("list_product_images", product_id: product.id, variant_id: child.id)[:items]).to be_empty
  end

  it "rejects inaccessible parents and invalid pagination" do
    restrict { |ability| ability.cannot :read, Spree::Product, id: product.id }
    expect { execute("list_product_images", product_id: product.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { execute("list_product_images", product_id: product.id, limit: 101) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end
end
