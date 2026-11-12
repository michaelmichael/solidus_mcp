# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::ListOptionTypes do
  include_context "tool execution"

  let!(:record) { create_option_type(name: "size", presentation: "Size") }
  let(:arguments) { {} }

  it "returns IDs and names with bounded pagination" do
    result = execute("list_option_types", **arguments, limit: 1)
    expect(result[:items].first).to include(id: record.id, name: record.name)
    expect(execute("list_option_types", **arguments, after_id: record.id)[:items]).to be_empty
  end

  it "returns a cursor only while more records remain" do
    second = create_option_type(name: "color", presentation: "Color")
    first_page = execute("list_option_types", **arguments, limit: 1)
    expect(first_page[:next_after_id]).to eq(record.id)
    last_page = execute("list_option_types", **arguments, after_id: first_page[:next_after_id], limit: 1)
    expect(last_page[:items].pluck(:id)).to eq([second.id])
    expect(last_page[:next_after_id]).to be_nil
  end

  it "rejects invalid pagination and undeclared inputs" do
    expect { execute("list_option_types", **arguments, limit: 0) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("list_option_types", **arguments, unknown: true) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "requires its dedicated connection grant" do
    @saved.update!(permissions: [])
    expect { execute("list_option_types", **arguments) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "requires OAuth read scope" do
    token.update!(scopes: "mcp:write")
    expect { execute("list_option_types", **arguments) }.to raise_error(SolidusMcp::InsufficientScope)
  end

  it "excludes unauthorized records" do
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::OptionType, id: record.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect(execute("list_option_types", **arguments)[:items]).to be_empty
  end

  it "filters literal names and presentations without wildcard expansion" do
    expect(execute("list_option_types", query: "SIZE")[:items].pluck(:id)).to eq([record.id])
    expect(execute("list_option_types", query: "%")[:items]).to be_empty
  end

  it "filters by an authorized product" do
    product.option_types << record
    create_option_type(name: "color", presentation: "Color")
    expect(execute("list_option_types", product_id: product.id)[:items].pluck(:id)).to eq([record.id])
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::Product, id: product.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("list_option_types", product_id: product.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
