# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Engine boot" do
  it "loads built-ins without host registration and uses real Solidus tables" do
    expect(defined?(StoreMcp)).to be_nil
    expect(Spree::Product.table_exists?).to be(true)
    expect(defined?(SolidusAdmin::Engine).present?).to eq(ENV["WITHOUT_ADMIN"] != "1")
  end

  it "eager loads the engine" do
    Rails.application.eager_load!
    expect(SolidusMcp::Tools::SearchOrders).to be < SolidusMcp::Tool
  end

  it "rebuilds metadata idempotently through the Rails prepare callback" do
    old_get_product = SolidusMcp.registry.tools.fetch("get_product")
    old_registry = SolidusMcp.registry.tools.keys
    Rails.application.reloader.prepare!
    new_registry = SolidusMcp.registry.tools.keys
    expect(new_registry).to match_array(old_registry)
    expect(SolidusMcp.registry.tools.fetch("get_product")).not_to equal(old_get_product)
  end
end
