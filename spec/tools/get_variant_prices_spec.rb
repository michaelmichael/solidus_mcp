# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::GetVariantPrices do
  include_context "tool execution"

  it "reads variant prices" do
    expect(execute("get_variant_prices", variant_id: product.master.id)[:items].first[:amount]).to eq("12.5")
  end
end
