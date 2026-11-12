# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::ShipShipment do
  include_context "external tool execution"
  let(:location) { Spree::StockLocation.create!(name: "Warehouse") }
  let(:shipping_method) do
    Spree::ShippingMethod.create!(name: "Ground", shipping_categories: [product.shipping_category],
      calculator: Spree::Calculator::Shipping::FlatRate.new)
  end
  let(:shipment) do
    country = Spree::Country.create!(name: "Testland", iso_name: "TESTLAND", iso: "TT", iso3: "TTT", states_required: false)
    address = Spree::Address.create!(name: "Test Customer", address1: "Test street", city: "Town", zipcode: "12345", phone: "5551234", country: country)
    order.update!(ship_address: address)
    line = Spree::LineItem.create!(order: order, variant: product.master, quantity: 1, price: "12.50")
    record = Spree::Shipment.create!(order: order, stock_location: location)
    Spree::ShippingRate.create!(shipment: record, shipping_method: shipping_method, selected: true, cost: 0)
    Spree::InventoryUnit.create!(shipment: record, line_item: line, variant: product.master, state: "on_hand")
    order.update_columns(state: "complete", completed_at: Time.current)
    record.update_columns(state: "ready")
    record
  end
  let(:arguments) { {shipment_id: shipment.id, tracking: "TRACK-1", notify_customer: false, idempotency_key: "ship-1"} }
  include_examples "a dedicated pending tool", "ship_shipment", -> { arguments }

  def ship(**overrides)
    execute("ship_shipment", **arguments.merge(overrides))
  end

  it "ships the explicit shipment through carton fulfillment without repeating it" do
    first = ship
    expect(first).to include(shipment_id: shipment.id, state: "shipped", tracking: "TRACK-1")
    expect(shipment.inventory_units.reload.pluck(:state)).to eq(["shipped"])
    expect(shipment.cartons.count).to eq(1)
    expect { expect(ship).to eq(first) }.not_to change(Spree::Carton, :count)
    expect { ship(tracking: "OTHER") }.to raise_error(SolidusMcp::ToolError, /different inputs/)
  end

  it "ships only the selected shipment and honors the explicit notification choice" do
    shipment
    second = Spree::Shipment.create!(order: order, stock_location: location)
    line = shipment.inventory_units.first.line_item
    line.update_columns(quantity: 2)
    other_unit = Spree::InventoryUnit.create!(shipment: second, line_item: line, variant: product.master, state: "backordered")
    delivery = double("mailer delivery", deliver_later: true)
    expect(Spree::Config.carton_shipped_email_class).to receive(:shipped_email).with(order: order, carton: an_instance_of(Spree::Carton)).and_return(delivery)
    ship(notify_customer: true)
    expect(second.reload.state).to eq("pending")
    expect(other_unit.reload.state).to eq("backordered")
  end

  it "requires update access when setting tracking" do
    shipment
    restrict { |ability| ability.cannot :update, Spree::Shipment, :tracking }
    expect { ship }.to raise_error(SolidusMcp::AccessDenied)
    expect(shipment.reload.state).to eq("ready")
    expect(shipment.tracking).to be_nil
  end

  it "rejects pending and backordered shipments before fulfillment" do
    shipment.update_columns(state: "pending")
    expect { ship }.to raise_error(SolidusMcp::ToolError, /ready/)
    shipment.update_columns(state: "ready")
    shipment.inventory_units.first.update_columns(state: "backordered")
    expect { ship }.to raise_error(SolidusMcp::ToolError, /ready/)
    expect(Spree::Carton.count).to eq(0)
  end

  it "checks access to affected inventory units" do
    unit = shipment.inventory_units.first
    restrict { |ability| ability.cannot :update, Spree::InventoryUnit, id: unit.id }
    expect { ship }.to raise_error(SolidusMcp::AccessDenied)
    expect(shipment.reload.state).to eq("ready")
  end

  it "authorizes the prospective carton with its real tracking and units" do
    shipment
    restrict { |ability| ability.cannot :create, Spree::Carton, tracking: "TRACK-1" }
    expect { ship }.to raise_error(SolidusMcp::AccessDenied)
    expect(shipment.reload.state).to eq("ready")
    expect(Spree::Carton.count).to eq(0)
  end

  it "requires an explicit notification choice" do
    expect { execute("ship_shipment", **arguments.except(:notify_customer)) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "keeps uncertain fulfillment failures blocked for reconciliation" do
    shipment
    allow_any_instance_of(Spree::OrderShipping).to receive(:ship_shipment).and_raise(IOError, "Notification failure")
    expect { ship }.to raise_error(SolidusMcp::ToolError, /reconcile/)
    expect(SolidusMcp::ToolRequest.last.status).to eq("uncertain")
    expect { ship }.to raise_error(SolidusMcp::ToolError, /reconciliation/)
  end
end
