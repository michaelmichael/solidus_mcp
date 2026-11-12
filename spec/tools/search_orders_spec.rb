# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::SearchOrders do
  include_context "tool execution"

  it "searches orders by number" do
    store = Spree::Store.create!(name: "Test", url: "example.test", code: "test", mail_from_address: "store@example.test")
    order = Spree::Order.create!(store: store, currency: "USD")
    expect(execute("search_orders", number: order.number)[:items].map { |row| row[:id] }).to eq([order.id])
  end
end
