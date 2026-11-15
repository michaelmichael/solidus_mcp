# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::CreateOptionValue do
  include_context "tool execution"

  let(:type) { create_option_type(name: "packs", presentation: "Packs") }

  def create_value(**changes)
    execute("create_option_value", option_type_id: type.id, name: "25-pack", presentation: "25-Pack", **changes)
  end

  def restrict(&block)
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end

  it "creates a value under its type with readable labels and default positioning" do
    product
    result = nil
    expect { result = create_value }.to change(Spree::OptionValue, :count).by(1)
    value = Spree::OptionValue.find(result[:option_value_id])
    expect(result).to eq(option_value_id: value.id, option_type_id: type.id, name: "25-pack",
      presentation: "25-Pack", option_type_name: "packs", option_type_presentation: "Packs", created: true)
    expect(type.reload.option_values).to eq([value])
    expect(value.position).to be_positive
    expect(value.variants).to be_empty
    expect(product.reload.option_types).to be_empty
    expect(execute("list_option_values", option_type_id: type.id)[:items]).to include(id: value.id, name: "25-pack", presentation: "25-Pack")
  end

  it "requires the dedicated permission and write scope" do
    @saved.update!(permissions: ["create_option_type", "list_option_values"])
    expect { create_value }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["create_option_value"])
    token.update!(scopes: "mcp:read")
    expect { create_value }.to raise_error(SolidusMcp::InsufficientScope)
  end

  it "requires value creation ability" do
    restrict { |a| a.cannot :create, Spree::OptionValue }
    expect { create_value }.to raise_error(SolidusMcp::AccessDenied)
    expect(Spree::OptionValue.count).to eq(0)
  end

  it "checks creation conditions against the populated value including its parent" do
    restrict { |a| a.cannot :create, Spree::OptionValue, option_type_id: type.id }
    expect { create_value }.to raise_error(SolidusMcp::AccessDenied)
    expect(type.reload.option_values).to be_empty
  end

  it "rejects missing and unauthorized parents without creating values" do
    expect { create_value(option_type_id: 2_000_000_000) }.to raise_error(ActiveRecord::RecordNotFound)
    restrict { |a| a.cannot :read, Spree::OptionType, id: type.id }
    expect { create_value }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Spree::OptionValue.count).to eq(0)
  end

  it "rejects blank labels and malformed inputs" do
    [{name: " "}, {presentation: "\n"}].each do |args|
      expect { create_value(**args) }.to raise_error(ActiveRecord::RecordInvalid)
    end
    [{name: ""}, {presentation: nil}, {presentation: "x" * 256}, {option_type_id: 0}, {option_type_id: "1"}, {position: 1}].each do |args|
      expect { create_value(**args) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    expect { execute("create_option_value", name: "x", presentation: "X") }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect(type.reload.option_values).to be_empty
  end

  it "enforces case-sensitive names within each type without changing existing values" do
    first = create_value
    value = Spree::OptionValue.find(first[:option_value_id])
    original = value.attributes
    restrict { |a| a.cannot :read, Spree::OptionValue, id: value.id }
    expect { create_value }.to raise_error(ActiveRecord::RecordInvalid, /Name has already been taken/)
    expect { create_value(presentation: "Different") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(value.reload.attributes).to eq(original)
    expect(create_value(name: "25-Pack")[:created]).to be(true)
    other = create_option_type(name: "other", presentation: "Other")
    expect(create_value(option_type_id: other.id)[:option_type_id]).to eq(other.id)
  end

  it "rechecks permissions after acquiring the type lock" do
    type
    allow_any_instance_of(Spree::OptionType).to receive(:with_lock).and_wrap_original do |method, &block|
      method.call do
        @saved.update!(permissions: [])
        block.call
      end
    end
    expect { create_value }.to raise_error(SolidusMcp::AccessDenied)
    expect(type.reload.option_values).to be_empty
  end

  it "rolls back creation when saving fails" do
    allow_any_instance_of(Spree::OptionValue).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    expect { create_value }.to raise_error(ActiveRecord::RecordInvalid)
    expect(type.reload.option_values).to be_empty
  end
end
