# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::CancelOrder do
  include_context "external tool execution"
  let(:arguments) { {order_id: order.id, reason: "Customer request", idempotency_key: "cancel-1"} }
  include_examples "a dedicated pending tool", "cancel_order", -> { arguments }

  def cancel(**overrides)
    execute("cancel_order", **arguments.merge(overrides))
  end

  def complete_order
    order.update_columns(state: "complete", completed_at: Time.current)
  end

  it "uses Solidus cancellation with actor/reason audit and does not repeat payment effects" do
    method = Spree::PaymentMethod::Check.create!(name: "Check")
    payment = Spree::Payment.create!(order: order, payment_method: method, amount: "20", state: "pending")
    complete_order
    result = cancel
    expect(result).to include(state: "canceled", canceled: true)
    expect(order.reload.canceler_id).to eq(user.id)
    expect(payment.reload.state).to eq("void")
    expect(SolidusMcp::ToolRequest.last.payload["reason"]).to eq("Customer request")
    expect(cancel).to eq(result)
    expect { cancel(reason: "Different") }.to raise_error(SolidusMcp::ToolError, /different inputs/)
  end

  it "rejects incomplete orders before effects and allows corrected retries" do
    expect { cancel }.to raise_error(SolidusMcp::ToolError, /complete/)
    expect(SolidusMcp::ToolRequest.last.status).to eq("failed")
    complete_order
    expect(cancel[:canceled]).to be(true)
  end

  it "restocks canceled shipment inventory once through Solidus movements" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    line = Spree::LineItem.create!(order: order, variant: product.master, quantity: 1, price: "12.50")
    shipment = Spree::Shipment.create!(order: order, stock_location: location)
    Spree::InventoryUnit.create!(shipment: shipment, line_item: line, variant: product.master, state: "on_hand")
    item = location.stock_items.find_by!(variant_id: product.master.id)
    original = item.count_on_hand
    complete_order
    cancel
    expect(shipment.reload.state).to eq("canceled")
    expect(item.reload.count_on_hand).to eq(original + 1)
    movements = Spree::StockMovement.where(stock_item_id: item.id).count
    cancel
    expect(item.reload.count_on_hand).to eq(original + 1)
    expect(Spree::StockMovement.where(stock_item_id: item.id).count).to eq(movements)
  end

  it "authorizes the actual restock quantity before starting effects" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    line = Spree::LineItem.create!(order: order, variant: product.master, quantity: 2, price: "12.50")
    shipment = Spree::Shipment.create!(order: order, stock_location: location)
    2.times { Spree::InventoryUnit.create!(shipment: shipment, line_item: line, variant: product.master, state: "on_hand") }
    complete_order
    restrict { |ability| ability.cannot :create, Spree::StockMovement, quantity: 2 }
    expect { cancel }.to raise_error(SolidusMcp::AccessDenied)
    expect(order.reload.state).to eq("complete")
    expect(Spree::StockMovement.count).to eq(0)
  end

  it "rejects orders with shipped shipments" do
    location = Spree::StockLocation.create!(name: "Warehouse")
    shipment = Spree::Shipment.create!(order: order, stock_location: location)
    shipment.update_columns(state: "shipped")
    complete_order
    expect { cancel }.to raise_error(SolidusMcp::ToolError, /pending or ready/)
    expect(order.reload.state).to eq("complete")
  end

  it "authorizes related payment cancellation before calling the workflow" do
    method = Spree::PaymentMethod::Check.create!(name: "Check")
    payment = Spree::Payment.create!(order: order, payment_method: method, amount: "20", state: "pending")
    complete_order
    restrict { |ability| ability.cannot :cancel, Spree::Payment, id: payment.id }
    expect { cancel }.to raise_error(SolidusMcp::AccessDenied)
    expect(order.reload.state).to eq("complete")
  end

  it "records uncertain partial external failure and blocks repeat effects" do
    method = Spree::PaymentMethod::Check.create!(name: "Check")
    Spree::Payment.create!(order: order, payment_method: method, amount: "20", state: "pending")
    complete_order
    allow_any_instance_of(Spree::Payment).to receive(:cancel!).and_raise(Spree::Core::GatewayError, "Timeout")
    expect { cancel }.to raise_error(SolidusMcp::ToolError, /reconcile/)
    expect(order.reload.state).to eq("complete")
    expect(SolidusMcp::ToolRequest.last.status).to eq("uncertain")
    expect { cancel }.to raise_error(SolidusMcp::ToolError, /reconciliation/)
  end

  it "requires an explicit nonblank reason and valid order ID" do
    expect { cancel(reason: " ") }.to raise_error(SolidusMcp::ToolError)
    expect { cancel(order_id: 0) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("cancel_order", **arguments.except(:reason)) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end
end
