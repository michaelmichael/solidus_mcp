# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Registry do
  it "automatically includes every built-in and no generic capability tools" do
    expect(SolidusMcp.registry.tools.size).to eq(12)
    expect(SolidusMcp.registry.tools.keys).to include("bulk_update_variant_prices", "search_orders")
    expect(SolidusMcp.registry.tools.keys).not_to include("list_capabilities", "describe_resource")
  end

  it "rejects duplicate names and permission reuse" do
    registry = described_class.new
    registry.register SolidusMcp::Tools::GetProduct
    expect { registry.register SolidusMcp::Tools::GetProduct }.to raise_error(ArgumentError, /Duplicate/)
    klass = Class.new(SolidusMcp::Tools::GetProduct) { tool_name :another_product_tool }
    stub_const("AnotherProductTool", klass)
    expect { registry.register klass }.to raise_error(ArgumentError, /unique/)
  end

  it "freezes schemas and catalog metadata" do
    tool = SolidusMcp.registry.tools.fetch("get_product")
    expect { tool.input_schema[:properties]["product_id"][:type].replace("string") }.to raise_error(FrozenError)
    expect { SolidusMcp.registry.tools.clear }.to raise_error(FrozenError)
  end
end
