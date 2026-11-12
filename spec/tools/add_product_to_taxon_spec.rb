# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::AddProductToTaxon do
  include_context "tool execution"

  let(:taxonomy) { Spree::Taxonomy.create!(name: "Categories") }
  let(:taxon) { Spree::Taxon.create!(taxonomy: taxonomy, parent: taxonomy.root, name: "Clothing") }
  let(:arguments) { {product_id: product.id, taxon_id: taxon.id} }

  def attach(**overrides)
    execute("add_product_to_taxon", **arguments.merge(overrides))
  end

  def restrict(&block)
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end

  it "adds a category without replacing existing classifications or changing variants" do
    existing = product.classifications.create!(taxon: taxonomy.root)
    variant = Spree::Variant.create!(product: product, sku: "CHILD", price: "12.50")
    variant_attributes = product.variants_including_master.order(:id).map(&:attributes)
    position = existing.position
    expect(attach).to eq(product_id: product.id, taxon_id: taxon.id, attached: true)
    expect(product.reload.taxon_ids).to match_array([taxonomy.root.id, taxon.id])
    expect(existing.reload.position).to eq(position)
    expect(product.variants_including_master.order(:id).map(&:attributes)).to eq(variant_attributes)
    expect(variant.reload.product_id).to eq(product.id)
  end

  it "appends after existing products in the target taxon" do
    other = create_product(sku: "OTHER")
    existing = taxon.classifications.create!(product: other)
    position = existing.position
    attach
    expect(existing.reload.position).to eq(position)
    expect(product.classifications.find_by!(taxon: taxon).position).to eq(position + 1)
    expect(taxon.products.reload.pluck(:id)).to eq([other.id, product.id])
  end

  it "does not duplicate or reorder an existing classification on retries" do
    attach
    first = product.classifications.find_by!(taxon: taxon)
    other = create_product(sku: "OTHER")
    second = taxon.classifications.create!(product: other)
    attributes = [first.reload.attributes, second.reload.attributes]
    expect { expect(attach[:attached]).to be(true) }.not_to change(Spree::Classification, :count)
    expect([first.reload.attributes, second.reload.attributes]).to eq(attributes)
  end

  it "requires positive integer IDs and rejects undeclared inputs" do
    [{product_id: 0}, {taxon_id: -1}, {taxon_id: "1"}, {taxon_id: nil}, {unknown: true}].each do |invalid|
      expect { attach(**invalid) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    arguments.each_key do |key|
      expect { execute("add_product_to_taxon", **arguments.except(key)) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  it "requires its dedicated grant and write scope" do
    @saved.update!(permissions: ["update_product", "list_taxons"])
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["add_product_to_taxon"])
    token.update!(scopes: "mcp:read")
    expect { attach }.to raise_error(SolidusMcp::InsufficientScope)
    token.update!(scopes: "mcp:write")
    expect(attach[:attached]).to be(true)
  end

  it "rejects missing records without adding classifications" do
    expect { attach(product_id: product.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { attach(taxon_id: taxon.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.classifications.count).to eq(0)
  end

  it "rejects inaccessible products" do
    restrict { |ability| ability.cannot :update, Spree::Product, id: product.id }
    expect { attach }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.classifications.count).to eq(0)
  end

  it "rejects inaccessible taxons" do
    restrict { |ability| ability.cannot :read, Spree::Taxon, id: taxon.id }
    expect { attach }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.classifications.count).to eq(0)
  end

  it "respects product taxon attribute restrictions" do
    restrict { |ability| ability.cannot :update, Spree::Product, :taxon_ids }
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.classifications.count).to eq(0)
  end

  it "authorizes the new classification with both parent IDs" do
    restrict { |ability| ability.cannot :create, Spree::Classification, product_id: product.id, taxon_id: taxon.id }
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.classifications.count).to eq(0)
  end

  it "requires Solidus classification creation ability" do
    restrict { |ability| ability.cannot :create, Spree::Classification }
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "rechecks record access on successful retries" do
    attach
    restrict { |ability| ability.cannot :read, Spree::Taxon, id: taxon.id }
    expect { attach }.to raise_error(ActiveRecord::RecordNotFound)
    expect(product.classifications.count).to eq(1)
  end

  it "rechecks grants after acquiring both locks" do
    taxon
    allow_any_instance_of(Spree::Taxon).to receive(:with_lock).and_wrap_original do |method, &block|
      method.call do
        @saved.update!(permissions: [])
        block.call
      end
    end
    expect { attach }.to raise_error(SolidusMcp::AccessDenied)
    expect(product.classifications.count).to eq(0)
  end

  it "preserves validations and rolls back failed classifications" do
    existing = product.classifications.create!(taxon: taxonomy.root)
    original = existing.attributes
    allow_any_instance_of(Spree::Classification).to receive(:valid?).and_return(false)
    expect { attach }.to raise_error(ActiveRecord::RecordInvalid)
    expect(product.classifications.reload).to eq([existing])
    expect(existing.reload.attributes).to eq(original)
  end
end
