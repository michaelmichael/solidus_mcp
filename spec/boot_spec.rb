# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Engine boot" do
  it "loads built-ins without host registration and uses real Solidus tables" do
    expect(defined?(StoreMcp)).to be_nil
    expect(Spree::Product.table_exists?).to be(true)
    expect(SolidusMcp.registry.tools.size).to eq(12)
    expect(defined?(SolidusAdmin::Engine).present?).to eq(ENV["WITHOUT_ADMIN"] != "1")
  end

  it "eager loads the engine" do
    Rails.application.eager_load!
    expect(SolidusMcp::Tools::SearchOrders).to be < SolidusMcp::Tool
  end

  it "rebuilds metadata idempotently through the Rails prepare callback" do
    old = SolidusMcp.registry.tools.fetch("get_product")
    Rails.application.reloader.prepare!
    expect(SolidusMcp.registry.tools.size).to eq(12)
    expect(SolidusMcp.registry.tools.fetch("get_product")).not_to equal(old)
  end
end
