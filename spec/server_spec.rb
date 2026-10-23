# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Server do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { TestCatalog::Credential.new(token, user) }
  let(:entry) { CatalogEntry.create!(name: "Example") }
  let(:server) { described_class.build(credential: credential, name: "test-catalog", version: "1.0", instructions: "Test catalog") }

  def rpc(method, params = {})
    JSON.parse(server.handle_json({jsonrpc: "2.0", id: 1, method: method, params: params}.to_json))
  end

  def call_tool(name, arguments = {})
    rpc("tools/call", {name: name, arguments: arguments})
  end

  it "lists only granted tools and generates exact resource schemas" do
    grant(application: application, user: user, permissions: ["entries.read"])
    names = rpc("tools/list").dig("result", "tools").map { |tool| tool.fetch("name") }
    expect(names).to contain_exactly("read_entry", "list_capabilities", "describe_resource")
    resource = call_tool("describe_resource", {resource: "entries"}).dig("result", "structuredContent")
    expect(resource.fetch("operations").map { |tool| tool.fetch("name") }).to eq(["read_entry"])
    expect(resource.dig("operations", 0, "input_schema", "required")).to eq(["id"])
  end

  it "executes a registered handler through the MCP SDK" do
    grant(application: application, user: user)
    expect(call_tool("publish_entry", {id: entry.id}).dig("result", "isError")).not_to be(true)
    expect(entry.reload).to be_published
  end

  it "blocks direct protocol calls to hidden operations" do
    grant(application: application, user: user, permissions: ["entries.read"])
    expect(call_tool("publish_entry", {id: entry.id})).to have_key("error")
    expect(entry.reload).not_to be_published
  end

  it "rechecks grants when a previously built server executes a tool" do
    saved = grant(application: application, user: user)
    server
    saved.update!(permissions: ["entries.read"])
    expect(call_tool("publish_entry", {id: entry.id}).dig("result", "isError")).to be(true)
    expect(entry.reload).not_to be_published
  end

  it "returns no capabilities for a disabled connection" do
    grant(application: application, user: user, enabled: false)
    expect(call_tool("list_capabilities").dig("result", "structuredContent", "resources")).to eq([])
    expect(call_tool("describe_resource", {resource: "entries"}).dig("result", "isError")).to be(true)
  end

  it "protects a handler called directly outside MCP" do
    expect { TestCatalog::Operations.new(credential).publish_entry(id: entry.id) }.to raise_error(SolidusMcp::AccessDenied)
    expect(entry.reload).not_to be_published
  end
end
