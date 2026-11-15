# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::CreateOptionType do
  include_context "tool execution"

  def create_type(**changes)
    execute("create_option_type", name: "packs", presentation: "Packs", **changes)
  end

  def restrict(&block)
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end

  it "creates a type with labels and default positioning without attaching products or creating values" do
    product
    result = nil
    expect { result = create_type }.to change(Spree::OptionType, :count).by(1)
    type = Spree::OptionType.find(result[:option_type_id])
    expect(result).to eq(option_type_id: type.id, name: "packs", presentation: "Packs", created: true)
    expect(type.position).to be_positive
    expect(type.option_values).to be_empty
    expect(product.reload.option_types).to be_empty
  end

  it "requires its dedicated permission and write scope" do
    @saved.update!(permissions: ["list_option_types", "create_option_value"])
    expect { create_type }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["create_option_type"])
    token.update!(scopes: "mcp:read")
    expect { create_type }.to raise_error(SolidusMcp::InsufficientScope)
  end

  it "checks class and populated record create abilities" do
    restrict { |a| a.cannot :create, Spree::OptionType }
    expect { create_type }.to raise_error(SolidusMcp::AccessDenied)
    expect(Spree::OptionType.count).to eq(0)
  end

  it "rejects names disallowed by record conditions before saving" do
    restrict { |a| a.cannot :create, Spree::OptionType, name: "packs" }
    expect { create_type }.to raise_error(SolidusMcp::AccessDenied)
    expect(Spree::OptionType.count).to eq(0)
  end

  it "rejects blank labels and invalid schemas without creating records" do
    [{name: " "}, {presentation: "\t"}].each do |args|
      expect { create_type(**args) }.to raise_error(ActiveRecord::RecordInvalid)
    end
    [{name: ""}, {presentation: nil}, {name: 1}, {name: "x" * 256}, {position: 3}, {option_values: []}].each do |args|
      expect { create_type(**args) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    expect { execute("create_option_type", name: "packs") }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect(Spree::OptionType.count).to eq(0)
  end

  it "preserves case-sensitive uniqueness and does not update or disclose an existing type" do
    result = create_type
    type = Spree::OptionType.find(result[:option_type_id])
    original = type.attributes
    restrict { |a| a.cannot :read, Spree::OptionType, id: type.id }
    expect { create_type }.to raise_error(ActiveRecord::RecordInvalid, /Name has already been taken/)
    expect { create_type(presentation: "Different") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(type.reload.attributes).to eq(original)
    expect(create_type(name: "Packs")[:created]).to be(true)
  end

  it "uses the standard MCP validation error response" do
    create_type
    server = SolidusMcp::Server.build(credential: credential)
    response = JSON.parse(server.handle_json(JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/call",
      params: {name: "create_option_type", arguments: {name: "packs", presentation: "Packs"}})))
    expect(response.dig("result", "isError")).to be(true)
    expect(response.dig("result", "content", 0, "text")).to include("Name has already been taken")
  end
end
