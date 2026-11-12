# frozen_string_literal: true

require_relative "tool_execution"
require "base64"

RSpec.shared_context "image tools" do
  include_context "tool execution"
  let(:png_base64) { "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=" }
  let(:image_arguments) { {product_id: product.id, filename: "pixel.png", content_type: "image/png", data_base64: png_base64, idempotency_key: "image-1"} }

  def upload_image(**overrides)
    execute("attach_product_image", **image_arguments.merge(overrides))
  end

  def restrict(&block)
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end
end

# Gateway claims must really commit before callbacks. These specs use separate
# committed records, and remove their own fixture rows in reverse FK order.
RSpec.shared_context "external tool execution" do
  include_context "tool execution"
  self.use_transactional_tests = false

  around do |example|
    tables = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
    baseline = tables.to_h do |table|
      pk = ActiveRecord::Base.connection.primary_key(table)
      [table, pk ? ActiveRecord::Base.connection.select_values("SELECT #{ActiveRecord::Base.connection.quote_column_name(pk)} FROM #{ActiveRecord::Base.connection.quote_table_name(table)}") : nil]
    end
    example.run
  ensure
    ActiveRecord::Base.transaction do
      # defer is not enough for immediate FKs; delete the new rows in FK order.
      remaining = baseline.select { |_table, ids| ids }
      until remaining.empty?
        progress = false
        remaining.keys.each do |table|
          ids = remaining.fetch(table)
          pk = ActiveRecord::Base.connection.primary_key(table)
          predicate = ids.empty? ? "TRUE" : "#{ActiveRecord::Base.connection.quote_column_name(pk)} NOT IN (#{ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(",")})"
          begin
            ActiveRecord::Base.transaction(requires_new: true) do
              ActiveRecord::Base.connection.execute("DELETE FROM #{ActiveRecord::Base.connection.quote_table_name(table)} WHERE #{predicate}")
            end
            remaining.delete(table)
            progress = true
          rescue ActiveRecord::InvalidForeignKey
            # A referencing fixture table will be removed first.
          end
        end
        raise "Could not clean external workflow fixtures" unless progress
      end
    end
  end

  let(:store) { Spree::Store.create!(name: "Test", url: "example.test", code: "test", mail_from_address: "store@example.test") }
  let(:order) { Spree::Order.create!(store: store, currency: "USD", email: "customer@example.test") }

  def restrict(&block)
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end
end

RSpec.shared_examples "a dedicated pending tool" do |name, valid_arguments|
  it "requires its dedicated connection grant" do
    @saved.update!(permissions: [])
    expect { execute(name, **instance_exec(&valid_arguments)) }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "requires the correct OAuth scope" do
    scope = SolidusMcp.registry.tools.fetch(name).read_only ? "mcp:write" : "mcp:read"
    token.update!(scopes: scope)
    expect { execute(name, **instance_exec(&valid_arguments)) }.to raise_error(SolidusMcp::InsufficientScope)
  end

  it "rejects undeclared arguments" do
    expect { execute(name, **instance_exec(&valid_arguments), unknown: true) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end
end
