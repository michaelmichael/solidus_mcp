# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::ListTaxons do
  include_context "tool execution"

  let!(:taxonomy) { Spree::Taxonomy.create!(name: "Categories") }
  let(:root) { taxonomy.root }
  let(:clothing) { Spree::Taxon.create!(taxonomy: taxonomy, parent: root, name: "Clothing") }
  let(:shirts) { Spree::Taxon.create!(taxonomy: taxonomy, parent: clothing, name: "Shirts", description: "Private description", meta_title: "Internal title") }

  def restrict(&block)
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end

  it "returns bounded hierarchy metadata without expanding ancestors or descendants" do
    shirts
    result = execute("list_taxons")
    expect(result[:items]).to eq([
      {id: root.id, name: "Categories", parent_id: nil, taxonomy_id: taxonomy.id, depth: 0},
      {id: clothing.id, name: "Clothing", parent_id: root.id, taxonomy_id: taxonomy.id, depth: 1},
      {id: shirts.id, name: "Shirts", parent_id: clothing.id, taxonomy_id: taxonomy.id, depth: 2}
    ])
    expect(result[:next_after_id]).to be_nil
  end

  it "distinguishes roots from an omitted parent filter" do
    shirts
    other = Spree::Taxonomy.create!(name: "Brands")
    expect(execute("list_taxons", parent_id: nil)[:items].pluck(:id)).to match_array([root.id, other.root.id])
    expect(execute("list_taxons")[:items].pluck(:id)).to include(clothing.id, shirts.id)
  end

  it "returns direct children rather than a recursive subtree" do
    shirts
    expect(execute("list_taxons", parent_id: root.id)[:items].pluck(:id)).to eq([clothing.id])
    expect(execute("list_taxons", parent_id: clothing.id)[:items].pluck(:id)).to eq([shirts.id])
    expect(execute("list_taxons", parent_id: shirts.id)).to eq(items: [], next_after_id: nil)
  end

  it "searches names case-insensitively and treats SQL wildcards literally" do
    shirts
    percent = Spree::Taxon.create!(taxonomy: taxonomy, parent: root, name: "100% Cotton")
    underscore = Spree::Taxon.create!(taxonomy: taxonomy, parent: root, name: "T_shirts")
    expect(execute("list_taxons", query: "SHIRT")[:items].pluck(:id)).to match_array([shirts.id, underscore.id])
    expect(execute("list_taxons", query: "%")[:items].pluck(:id)).to eq([percent.id])
    expect(execute("list_taxons", query: "_")[:items].pluck(:id)).to eq([underscore.id])
    expect(execute("list_taxons", query: "' OR 1=1 --")[:items]).to be_empty
  end

  it "combines taxonomy, parent, and name filters" do
    shirts
    other = Spree::Taxonomy.create!(name: "Brands")
    Spree::Taxon.create!(taxonomy: other, parent: other.root, name: "Shirts")
    result = execute("list_taxons", taxonomy_id: taxonomy.id, parent_id: clothing.id, query: "shirt")
    expect(result[:items].pluck(:id)).to eq([shirts.id])
    expect(execute("list_taxons", taxonomy_id: other.id, parent_id: clothing.id)[:items]).to be_empty
  end

  it "disambiguates identical names in different branches with parent and taxonomy IDs" do
    shirts
    sibling = Spree::Taxon.create!(taxonomy: taxonomy, parent: root, name: "Shirts")
    result = execute("list_taxons", query: "Shirts")[:items]
    expect(result.pluck(:id)).to match_array([shirts.id, sibling.id])
    expect(result.pluck(:parent_id)).to match_array([root.id, clothing.id])
  end

  it "paginates by ID even when nested-set tree order differs" do
    shirts
    late = Spree::Taxon.create!(taxonomy: taxonomy, parent: root, name: "Accessories")
    late.move_to_left_of(clothing)
    ids = []
    cursor = 0
    loop do
      result = execute("list_taxons", after_id: cursor, limit: 1)
      ids.concat(result[:items].pluck(:id))
      cursor = result[:next_after_id]
      break unless cursor
    end
    expect(ids).to eq([root.id, clothing.id, shirts.id, late.id])
    expect(execute("list_taxons", after_id: late.id)).to eq(items: [], next_after_id: nil)
  end

  it "excludes unauthorized taxons before applying the page limit" do
    shirts
    restrict { |ability| ability.cannot :read, Spree::Taxon, id: clothing.id }
    first_page = execute("list_taxons", limit: 1)
    expect(first_page[:items].pluck(:id)).to eq([root.id])
    last_page = execute("list_taxons", limit: 1, after_id: first_page[:next_after_id])
    expect(last_page[:items].pluck(:id)).to eq([shirts.id])
    expect(last_page[:next_after_id]).to be_nil
    expect(last_page[:items].first.keys).to match_array(%i[id name parent_id taxonomy_id depth])
  end

  it "authorizes an explicit parent even when its child is readable" do
    shirts
    restrict { |ability| ability.cannot :read, Spree::Taxon, id: clothing.id }
    expect { execute("list_taxons", parent_id: clothing.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(execute("list_taxons", query: "Shirts")[:items].pluck(:id)).to eq([shirts.id])
  end

  it "authorizes an explicit taxonomy filter" do
    shirts
    restrict { |ability| ability.cannot :read, Spree::Taxonomy, id: taxonomy.id }
    expect { execute("list_taxons", taxonomy_id: taxonomy.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(execute("list_taxons")[:items].pluck(:id)).to include(shirts.id)
  end

  it "rejects missing parent and taxonomy records" do
    expect { execute("list_taxons", parent_id: root.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { execute("list_taxons", taxonomy_id: taxonomy.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "returns an empty page when all taxons are hidden" do
    restrict { |ability| ability.cannot :read, Spree::Taxon, id: root.id }
    expect(execute("list_taxons")).to eq(items: [], next_after_id: nil)
  end

  it "validates filters and pagination, allowing null only for the parent filter" do
    [{parent_id: 0}, {parent_id: "1"}, {parent_id: false}, {taxonomy_id: 0}, {taxonomy_id: nil},
      {query: ""}, {query: "x" * 101}, {query: nil}, {limit: 0}, {limit: 101},
      {after_id: -1}, {after_id: "1"}, {unknown: true}].each do |arguments|
      expect { execute("list_taxons", **arguments) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  it "requires its dedicated grant and read scope" do
    @saved.update!(permissions: ["search_products"])
    expect { execute("list_taxons") }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["list_taxons"])
    token.update!(scopes: "mcp:write")
    expect { execute("list_taxons") }.to raise_error(SolidusMcp::InsufficientScope)
    token.update!(scopes: "mcp:read")
    expect(execute("list_taxons")[:items].pluck(:id)).to eq([root.id])
  end

  it "requires Solidus taxon read ability" do
    restrict { |ability| ability.cannot :read, Spree::Taxon }
    expect { execute("list_taxons") }.to raise_error(SolidusMcp::AccessDenied)
  end
end
