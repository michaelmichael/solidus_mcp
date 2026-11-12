# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::CreateVariantPrice do
  include_context "tool execution"
  let(:arguments) { {variant_id: product.master.id, currency: "EUR", country_iso: nil, amount: "18.95"} }
  include_examples "a dedicated pending tool", "create_variant_price", -> { arguments }

  it "creates an explicit context and returns the same row on identical retry" do
    first = execute("create_variant_price", **arguments)
    expect(first).to include(currency: "EUR", country_iso: nil, amount: "18.95")
    expect { expect(execute("create_variant_price", **arguments)).to eq(first) }.not_to change(Spree::Price, :count)
    expect { execute("create_variant_price", **arguments.merge(amount: "20")) }.to raise_error(SolidusMcp::ToolError)
  end

  it "rejects ambiguous contexts and does not add another row" do
    2.times { Spree::Price.create!(variant: product.master, currency: "EUR", amount: "18.95") }
    expect { execute("create_variant_price", **arguments) }.to raise_error(SolidusMcp::ToolError, /ambiguous/)
  end

  it "requires explicit nullable country, decimal strings, and Solidus-valid currency/country" do
    expect { execute("create_variant_price", **arguments.except(:country_iso)) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("create_variant_price", **arguments.merge(amount: 5)) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("create_variant_price", **arguments.merge(amount: "-1")) }.to raise_error(SolidusMcp::ToolError)
    expect { execute("create_variant_price", **arguments.merge(currency: "ZZZ")) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { execute("create_variant_price", **arguments.merge(country_iso: "ZZ")) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "authorizes the new price and variant parent" do
    ability = Spree::Ability.new(user)
    ability.cannot :create, Spree::Price, currency: "EUR"
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("create_variant_price", **arguments) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "does not create a context hidden by record permissions" do
    Spree::Price.create!(variant: product.master, currency: "EUR", amount: "18.95")
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::Price, currency: "EUR"
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { execute("create_variant_price", **arguments) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "rejects custom pricing options" do
    arguments
    allow(Spree::Config).to receive(:pricing_options_class).and_return(Object)
    expect { execute("create_variant_price", **arguments) }.to raise_error(SolidusMcp::ToolError, /Custom/)
  end
end
