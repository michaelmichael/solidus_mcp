# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::AddProductOptionType do
  include_context "tool execution"

  let(:option_type) { create_option_type(name: "size", presentation: "Size") }
  let(:arguments) { {product_id: product.id, option_type_id: option_type.id} }

  def attach(**overrides)
    execute("add_product_option_type", **arguments.merge(overrides))
  end

  it "adds an option type without replacing existing options or changing variants" do
    existing = create_option_type(name: "color", presentation: "Color")
    product.option_types << existing
    variant = Spree::Variant.create!(product: product, sku: "CHILD", price: "12.50")
    variant_attributes = product.variants_including_master.order(:id).map(&:attributes)
    existing_position = product.product_option_types.find_by!(option_type: existing).position

    expect(attach).to eq(product_id: product.id, option_type_id: option_type.id, attached: true)
    expect(product.reload.option_type_ids).to match_array([existing.id, option_type.id])
    expect(product.product_option_types.find_by!(option_type: existing).position).to eq(existing_position)
    expect(product.product_option_types.find_by!(option_type: option_type).position).to be > existing_position
    expect(product.variants_including_master.order(:id).map(&:attributes)).to eq(variant_attributes)
    expect(variant.reload.product_id).to eq(product.id)
  end

  it "does not duplicate or reorder associations on retries" do
    attach
    attachment = product.product_option_types.find_by!(option_type: option_type)
    expect { attach }.not_to change(Spree::ProductOptionType, :count)
    expect(attachment.reload.position).to eq(1)
  end

  it "requires both positive integer IDs and rejects extra inputs" do
    [{product_id: 0}, {option_type_id: -1}, {option_type_id: "1"}, {unknown: true}].each do |invalid|
      expect { attach(**invalid) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    expect { execute("add_product_option_type", product_id: product.id) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { execute("add_product_option_type", option_type_id: option_type.id) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "requires its own grant rather than the product update grant" do
    @saved.update!(permissions: ["update_product"])
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "requires OAuth write consent" do
    token.update!(scopes: "mcp:read")
    expect { attach }.to raise_error(SolidusMcp::InsufficientScope)
  end

  it "works with only its dedicated grant and write scope" do
    @saved.update!(permissions: ["add_product_option_type"])
    token.update!(scopes: "mcp:write")
    expect(attach[:attached]).to be(true)
  end

  it "rejects missing records without adding an association" do
    expect { attach(product_id: product.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { attach(option_type_id: option_type.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.product_option_types.count).to eq(0)
  end

  it "rejects products the user cannot update" do
    ability = Spree::Ability.new(user)
    ability.cannot :update, Spree::Product, id: product.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { attach }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.product_option_types.count).to eq(0)
  end

  it "rejects option types the user cannot read" do
    ability = Spree::Ability.new(user)
    ability.cannot :read, Spree::OptionType, id: option_type.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { attach }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.product_option_types.count).to eq(0)
  end

  it "authorizes the new association before saving" do
    ability = Spree::Ability.new(user)
    ability.cannot :create, Spree::ProductOptionType, product_id: product.id
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.product_option_types.count).to eq(0)
  end

  it "rechecks connection permissions after acquiring the product lock" do
    product
    allow_any_instance_of(Spree::Product).to receive(:with_lock).and_wrap_original do |method, &block|
      method.call do
        @saved.update!(permissions: [])
        block.call
      end
    end
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.product_option_types.count).to eq(0)
  end

  it "preserves association validations and rolls back failed attachments" do
    allow_any_instance_of(Spree::ProductOptionType).to receive(:valid?).and_return(false)
    expect { attach }.to raise_error(ActiveRecord::RecordInvalid)
    expect(product.product_option_types.count).to eq(0)
  end
end
