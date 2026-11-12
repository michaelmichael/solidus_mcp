# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::GetOrderStatus do
  include_context "tool execution"

  it "reads order status" do
    store = Spree::Store.create!(name: "Test", url: "example.test", code: "test", mail_from_address: "store@example.test")
    order = Spree::Order.create!(store: store, currency: "USD")
    expect(execute("get_order_status", order_id: order.id)[:state]).to eq("cart")
  end
end
