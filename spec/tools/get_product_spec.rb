# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::GetProduct do
  include_context "tool execution"

  it "returns the authorized product and rejects inaccessible records" do
    expect(execute("get_product", product_id: product.id)).to include("id" => product.id)
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::Product, id: product.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("get_product", product_id: product.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
