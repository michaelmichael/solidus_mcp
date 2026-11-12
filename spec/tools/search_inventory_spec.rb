# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::SearchInventory do
  include_context "tool execution"

  it "searches inventory by SKU" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    item = location.stock_items.find_or_create_by!(variant: product.master)
    expect(execute("search_inventory", query: product.master.sku)[:items].map { |row| row[:id] }).to include(item.id)
  end
end
