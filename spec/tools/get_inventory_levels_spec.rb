# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::GetInventoryLevels do
  include_context "tool execution"

  it "reads stock levels by variant" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    item = location.stock_items.find_or_create_by!(variant: product.master)
    expect(execute("get_inventory_levels", variant_id: product.master.id)[:items].map { |row| row[:id] }).to include(item.id)
  end
end
