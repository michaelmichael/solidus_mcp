# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::PublishProduct do
  include_context "tool execution"
  include_examples "a dedicated pending tool", "publish_product", -> { {product_id: product.id} }

  it "publishes availability and is safe to repeat" do
    product.update!(available_on: nil)
    variants = product.variants_including_master.map(&:attributes)
    execute("publish_product", product_id: product.id)
    expect(product.reload.available?).to be(true)
    expect(Spree::Product.available.exists?(product.id)).to be(true)
    original = product.available_on
    execute("publish_product", product_id: product.id)
    expect(product.reload.available_on).to eq(original)
    expect(product.variants_including_master.map(&:attributes)).to eq(variants)
  end

  it "requires record and availability attribute access" do
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Product, :available_on
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("publish_product", product_id: product.id) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "rejects missing products and invalid IDs" do
    expect { execute("publish_product", product_id: product.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { execute("publish_product", product_id: 0) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "rejects discontinued products without changing their lifecycle fields" do
    product.update!(available_on: nil, discontinue_on: 1.day.ago)
    expect { execute("publish_product", product_id: product.id) }.to raise_error(SolidusMcp::ToolError, /Discontinued/)
    expect(product.reload.available_on).to be_nil
    expect(product.discontinued?).to be(true)
  end
end
