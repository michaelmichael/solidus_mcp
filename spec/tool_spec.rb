# frozen_string_literal: true

require "spec_helper"

module TestCatalog
  class PublishEntry < SolidusMcp::Tool
    tool_name :publish_entry
    resource :entries
    permissions "entries.publish"
    scope "products:write"
    description "Publish a catalog entry"
    read_only false
    input :id, type: "integer", minimum: 1, required: true

    def call(id:)
      authorize!
      record = policy.scope(CatalogEntry, :update).find(id)
      record.assign_attributes(published: true)
      policy.authorize_record!(:update, record)
      record.save!
      {id: record.id, published: record.published}
    end
  end
end

RSpec.describe SolidusMcp::Tool do
  let(:registry) do
    # Build a fresh registry; keep a legacy handler alongside the class tool.
    registry = SolidusMcp::Registry.new
    registry.resource :entries, model: "CatalogEntry", label: "Entries", actions: {read: :read, publish: :update}
    registry.tool :read_entry, resource: :entries, permissions: ["entries.read"], handler: "TestCatalog::Operations",
      definition: {scope: "catalog:read", description: "Read", read_only: true, properties: {id: {type: "integer"}}, required: ["id"]}
    registry.register TestCatalog::PublishEntry
    registry.seal!
  end
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { TestCatalog::Credential.new(token, user) }
  let(:entry) { CatalogEntry.create!(name: "Example") }
  let(:server) { SolidusMcp::Server.build(credential: credential, name: "test", version: "1", instructions: "Test") }

  before { SolidusMcp.registry = registry }

  def rpc(method, params = {})
    JSON.parse(server.handle_json({jsonrpc: "2.0", id: 1, method: method, params: params}.to_json))
  end

  def publish
    rpc("tools/call", name: "publish_entry", arguments: {id: entry.id})
  end

  it "runs legacy and class handlers through the same server" do
    grant(application: application, user: user)
    expect(rpc("tools/call", name: "read_entry", arguments: {id: entry.id}).dig("result", "structuredContent", "id")).to eq(entry.id)
    expect(publish.dig("result", "structuredContent", "published")).to be(true)
    expect(entry.reload).to be_published
    schema = rpc("tools/list").dig("result", "tools").find { |tool| tool["name"] == "publish_entry" }.fetch("inputSchema")
    expect(schema).to include("required" => ["id"], "additionalProperties" => false)
  end

  it "denies discovery and direct execution until granted" do
    expect(rpc("tools/list").dig("result", "tools").map { |tool| tool["name"] }).not_to include("publish_entry")
    expect(publish).to have_key("error")
    expect { TestCatalog::PublishEntry.new(credential).call(id: entry.id) }.to raise_error(SolidusMcp::AccessDenied)
    expect(entry.reload).not_to be_published
  end

  it "rechecks revocation after discovery" do
    connection = grant(application: application, user: user)
    server
    connection.update!(permissions: ["entries.read"])
    expect(TestCatalog::PublishEntry).not_to receive(:new)
    expect(publish.dig("result", "isError")).to be(true)
    expect(entry.reload).not_to be_published
  end

  it "requires OAuth scope even with a connection grant" do
    grant(application: application, user: user)
    token.update!(scopes: "catalog:read")
    expect(publish).to have_key("error")
  end

  it "keeps subclass input declarations independent" do
    subclass = Class.new(TestCatalog::PublishEntry) do
      input :reason, type: "string", required: true
    end
    expect(subclass.registration[:definition][:required]).to eq(%w[id reason])
    expect(TestCatalog::PublishEntry.registration[:definition][:required]).to eq(["id"])
    expect { registry.tools["publish_entry"].input_schema[:properties]["id"][:type].replace("string") }.to raise_error(FrozenError)
  end

  it "rejects invalid class registrations and reuses registry validation" do
    fresh = SolidusMcp::Registry.new
    expect { fresh.register(Class.new(TestCatalog::PublishEntry)) }.to raise_error(ArgumentError, /named/)
    expect { fresh.register(String) }.to raise_error(ArgumentError, /subclass/)
    expect { fresh.register(TestCatalog::PublishEntry) }.to raise_error(ArgumentError, /Unknown resource/)
    fresh.resource :entries, model: "CatalogEntry", label: "Entries", actions: {read: :read}
    expect { fresh.register(TestCatalog::PublishEntry) }.to raise_error(ArgumentError, /Unknown permission/)
  end

  it "resolves the current class after a Rails-style constant replacement" do
    grant(application: application, user: user)
    server
    replacement = Class.new(TestCatalog::PublishEntry) do
      def call(id:)
        authorize!
        {id: id, reloaded: true}
      end
    end
    stub_const("TestCatalog::PublishEntry", replacement)
    expect(publish.dig("result", "structuredContent", "reloaded")).to be(true)
  end
end
