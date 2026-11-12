# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::UnpublishProduct do
  include_context "tool execution"
  include_examples "a dedicated pending tool", "unpublish_product", -> { {product_id: product.id} }

  it "withdraws availability and is safe to repeat" do
    product.update!(available_on: 1.day.ago)
    variants = product.variants_including_master.map(&:attributes)
    execute("unpublish_product", product_id: product.id)
    expect(product.reload.available?).to be_falsey
    expect(Spree::Product.available.exists?(product.id)).to be(false)
    original = product.available_on
    execute("unpublish_product", product_id: product.id)
    expect(product.reload.available_on).to eq(original)
    expect(product.variants_including_master.map(&:attributes)).to eq(variants)
  end

  it "requires record and availability attribute access" do
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Product, :available_on
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("unpublish_product", product_id: product.id) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "rejects missing products and invalid IDs" do
    expect { execute("unpublish_product", product_id: product.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { execute("unpublish_product", product_id: 0) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "preserves discontinuation and does not delete products" do
    product.update!(available_on: 1.day.ago, discontinue_on: 1.day.ago)
    original = product.reload.discontinue_on
    execute("unpublish_product", product_id: product.id)
    expect(product.reload.discontinue_on).to eq(original)
    expect(product.deleted_at).to be_nil
  end
end
