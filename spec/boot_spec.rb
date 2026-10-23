# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Standalone host" do
  it "boots only the requested admin mode" do
    expect(defined?(SolidusAdmin::Engine).present?).to eq(ENV["WITHOUT_ADMIN"] != "1")
    expect(Rails.root.to_s).to end_with("spec/dummy")
    expect(defined?(StoreMcp)).to be_nil
  end

  it "loads policy models without a store schema" do
    expect(SolidusMcp::ConnectionPolicy.table_exists?).to be(true)
    expect(SolidusMcp::PolicyChange.table_exists?).to be(true)
    expect(ActiveRecord::Base.connection.table_exists?(:spree_products)).to be(false)
  end
end
