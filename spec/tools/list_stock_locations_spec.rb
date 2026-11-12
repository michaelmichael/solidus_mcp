# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::ListStockLocations do
  include_context "tool execution"

  let!(:location) do
    Spree::StockLocation.create!(name: "Warehouse", active: false, default: true,
      fulfillable: false, backorderable_default: true, propagate_all_variants: false,
      restock_inventory: false, address1: "Private street", phone: "555-1234", email: "private@example.test")
  end

  it "returns only IDs, names, and operational flags, including inactive locations" do
    expect(execute("list_stock_locations")).to eq(items: [{id: location.id, name: "Warehouse",
                                                           active: false, default: true, fulfillable: false, backorderable_default: true,
                                                           propagate_all_variants: false, restock_inventory: false}], next_after_id: nil)
  end

  it "paginates authorized locations in ID order" do
    hidden = Spree::StockLocation.create!(name: "Hidden")
    second = Spree::StockLocation.create!(name: "Second")
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::StockLocation, id: hidden.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    first_page = execute("list_stock_locations", limit: 1)
    expect(first_page[:items].pluck(:id)).to eq([location.id])
    expect(first_page[:next_after_id]).to eq(location.id)
    last_page = execute("list_stock_locations", after_id: first_page[:next_after_id], limit: 1)
    expect(last_page[:items].pluck(:id)).to eq([second.id])
    expect(last_page[:next_after_id]).to be_nil
    expect(execute("list_stock_locations", after_id: second.id)[:items]).to be_empty
  end

  it "returns an empty page when no locations are authorized" do
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::StockLocation, id: location.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect(execute("list_stock_locations")).to eq(items: [], next_after_id: nil)
  end

  it "rejects invalid pagination and undeclared inputs" do
    [{limit: 0}, {limit: 101}, {after_id: -1}, {limit: "1"}, {query: "Warehouse"}].each do |arguments|
      expect { execute("list_stock_locations", **arguments) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  it "requires its dedicated grant and read scope" do
    @saved.update!(permissions: ["get_inventory_levels"])
    expect { execute("list_stock_locations") }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["list_stock_locations"])
    token.update!(scopes: "mcp:write")
    expect { execute("list_stock_locations") }.to raise_error(SolidusMcp::InsufficientScope)
    token.update!(scopes: "mcp:read")
    expect(execute("list_stock_locations")[:items].pluck(:id)).to eq([location.id])
  end

  it "requires Solidus stock location read ability" do
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::StockLocation
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("list_stock_locations") }.to raise_error(SolidusMcp::AccessDenied)
  end
end
