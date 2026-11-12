# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::GetProductVariants do
  include_context "tool execution"

  it "lists product variants" do
    variant = execute("get_product_variants", product_id: product.id)[:items].first
    expect(variant["sku"]).to eq("SKU-1")
  end
end
