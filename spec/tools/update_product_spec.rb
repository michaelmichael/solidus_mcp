# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::UpdateProduct do
  include_context "tool execution"

  it "updates supported attributes and preserves Solidus validations" do
    execute("update_product", product_id: product.id, changes: {description: "New description"})
    expect(product.reload.description).to eq("New description")
    expect { execute("update_product", product_id: product.id, changes: {name: ""}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("update_product", product_id: product.id, changes: {price: 1}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("update_product", product_id: product.id, changes: {name: " "}) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(product.reload.name).to eq("Test product")
  end

  it "enforces record restrictions before changing a product" do
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Product, id: product.id
    allow(Spree::Ability).to receive(:new).and_return(ability)
    expect { execute("update_product", product_id: product.id, changes: {description: "Denied"}) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.reload.description).not_to eq("Denied")
  end
end
