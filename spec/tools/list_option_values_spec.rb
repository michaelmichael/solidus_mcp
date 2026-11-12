# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::ListOptionValues do
  include_context "tool execution"

  let!(:option_type) { create_option_type(name: "size", presentation: "Size") }
  let!(:record) { Spree::OptionValue.create!(option_type: option_type, name: "small", presentation: "Small") }
  let(:arguments) { {option_type_id: option_type.id} }

  it "returns IDs and names with bounded pagination" do
    result = execute("list_option_values", **arguments, limit: 1)
    expect(result[:items].first).to include(id: record.id, name: record.name)
    expect(execute("list_option_values", **arguments, after_id: record.id)[:items]).to be_empty
  end

  it "returns a cursor only while more records remain" do
    second = Spree::OptionValue.create!(option_type: option_type, name: "large", presentation: "Large")
    first_page = execute("list_option_values", **arguments, limit: 1)
    expect(first_page[:next_after_id]).to eq(record.id)
    last_page = execute("list_option_values", **arguments, after_id: first_page[:next_after_id], limit: 1)
    expect(last_page[:items].pluck(:id)).to eq([second.id])
    expect(last_page[:next_after_id]).to be_nil
  end

  it "rejects invalid pagination and undeclared inputs" do
    expect { execute("list_option_values", **arguments, limit: 0) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("list_option_values", **arguments, unknown: true) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "requires its dedicated connection grant" do
    @saved.update!(permissions: [])
    expect { execute("list_option_values", **arguments) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "requires OAuth read scope" do
    token.update!(scopes: "mcp:write")
    expect { execute("list_option_values", **arguments) }.to raise_error(SolidusMcp::InsufficientScope)
  end

  it "excludes unauthorized records" do
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::OptionValue, id: record.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect(execute("list_option_values", **arguments)[:items]).to be_empty
  end

  it "requires an existing authorized parent and does not return other types' values" do
    other = create_option_type(name: "color", presentation: "Color")
    Spree::OptionValue.create!(option_type: other, name: "red", presentation: "Red")
    expect(execute("list_option_values", **arguments)[:items].pluck(:id)).to eq([record.id])
    expect { execute("list_option_values") }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("list_option_values", option_type_id: 0) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::OptionType, id: option_type.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("list_option_values", **arguments) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
