# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::SearchProducts do
  include_context "tool execution"

  it "searches products by variant SKU" do
    product
    expect(execute("search_products", query: "SKU-1")[:items].first["id"]).to eq(product.id)
  end
end
