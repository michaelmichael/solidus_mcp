# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Registry do
  it "automatically includes every built-in and no generic capability tools" do
    builtin_tools = SolidusMcp::BUILTIN_TOOLS.map { |t| t.constantize.registration[:tool_name].to_s }
    registry_tools = SolidusMcp.registry.tools.keys
    expect(registry_tools).to match_array(builtin_tools)
    expect(registry_tools).not_to include("list_capabilities", "describe_resource", "set_stock")
  end

  it "keeps each built-in tool and its specs in separate files" do
    SolidusMcp::BUILTIN_TOOLS.each do |class_name|
      filename = class_name.demodulize.underscore
      expect(SolidusMcp::Engine.root.join("app/tools/solidus_mcp/tools/#{filename}.rb")).to exist
      expect(SolidusMcp::Engine.root.join("spec/tools/#{filename}_spec.rb")).to exist
    end
  end

  it "rejects duplicate names and permission reuse" do
    registry = described_class.new
    registry.register SolidusMcp::Tools::GetProduct
    expect { registry.register SolidusMcp::Tools::GetProduct }.to raise_error(ArgumentError, /Duplicate/)
    klass = Class.new(SolidusMcp::Tools::GetProduct) { tool_name :another_product_tool }
    stub_const("AnotherProductTool", klass)
    expect { registry.register klass }.to raise_error(ArgumentError, /unique/)
  end

  it "rejects audit classifications that contradict the OAuth read/write declaration" do
    klass = Class.new(SolidusMcp::Tools::GetProduct) do
      tool_name :invalid_audit_type
      permission "invalid_audit_type"
      audit_action "delete"
    end
    stub_const("InvalidAuditType", klass)
    expect { described_class.new.register(klass) }.to raise_error(ArgumentError, /Audit action/)
  end

  it "freezes schemas and catalog metadata" do
    tool = SolidusMcp.registry.tools.fetch("get_product")
    expect { tool.input_schema[:properties]["product_id"][:type].replace("string") }.to raise_error(FrozenError)
    expect { SolidusMcp.registry.tools.clear }.to raise_error(FrozenError)
  end
end
