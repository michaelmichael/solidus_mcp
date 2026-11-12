# frozen_string_literal: true

require "spec_helper"
require_relative "support/tool_execution"

RSpec.describe "MCP activity auditing" do
  include_context "tool execution"

  it "records actor, client, tool, classification, input targets and returned IDs" do
    result = execute("get_product", product_id: product.id)
    event = SolidusMcp::ActivityEvent.last
    expect(event).to have_attributes(user_id: user.id, application_id: application.id,
      application_uid: application.uid, token_id: token.id, protocol_method: "tools/call",
      tool_name: "get_product", action: "read", status: "succeeded", actor_role: "superadmin")
    expect(event.resource_ids).to eq("product_id" => product.id, "result" => {"returned_ids" => [result["id"]]})
    expect(event.duration_ms).to be >= 0
    expect(event.finished_at).to be >= event.started_at
  end

  it "records requested field names without values, raw arguments, or response content" do
    execute("update_product", product_id: product.id, changes: {description: "PRIVATE-CUSTOMER-CONTENT"})
    event = SolidusMcp::ActivityEvent.last
    expect(event.action).to eq("update")
    expect(event.changed_fields).to eq(["description"])
    expect(event.attributes.to_json).not_to include("PRIVATE-CUSTOMER-CONTENT", token.token)
  end

  it "records created identities and delete classifications" do
    category = Spree::ShippingCategory.create!(name: "Default")
    result = execute("create_product", name: "Draft", price: 5, shipping_category_id: category.id)
    event = SolidusMcp::ActivityEvent.last
    expect(event.action).to eq("create")
    expect(event.resource_ids.dig("result", "product_id")).to eq(result[:product_id])
    expect(SolidusMcp.registry.tools.fetch("remove_product_image").audit_action).to eq("delete")
  end

  it "records connection and OAuth denials" do
    @saved.update!(permissions: [])
    expect { execute("get_product", product_id: product.id) }.to raise_error(SolidusMcp::AccessDenied)
    expect(SolidusMcp::ActivityEvent.last.status).to eq("denied")
    @saved.update!(permissions: ["get_product"])
    token.update!(scopes: "mcp:write")
    expect { execute("get_product", product_id: product.id) }.to raise_error(SolidusMcp::InsufficientScope)
    expect(SolidusMcp::ActivityEvent.last).to have_attributes(status: "denied", error_class: "SolidusMcp::InsufficientScope")
  end

  it "records invalid input and failures after a tool transaction rolls back" do
    expect { execute("get_product", product_id: 0) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect(SolidusMcp::ActivityEvent.last.status).to eq("failed")
    original = product.name
    expect { execute("update_product", product_id: product.id, changes: {name: " "}) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(product.reload.name).to eq(original)
    expect(SolidusMcp::ActivityEvent.last).to have_attributes(status: "failed", error_class: "ActiveRecord::RecordInvalid")
  end

  it "records partial batch outcomes and safe result IDs without copying SKU or error text" do
    product
    execute("bulk_update_variant_prices", entries: [
      {sku: "SKU-1", amount: "19.95", currency: "USD", country_iso: nil},
      {sku: "PRIVATE-SKU", amount: "19.95", currency: "USD", country_iso: nil}
    ])
    event = SolidusMcp::ActivityEvent.last
    expect(event.status).to eq("partial")
    expect(event.resource_ids.dig("result", "batch").pluck("success")).to eq([true, false])
    expect(event.resource_ids.dig("result", "batch", 0, "variant_id")).to eq(product.master.id)
    expect(event.attributes.to_json).not_to include("PRIVATE-SKU", "19.95")
  end

  it "does not copy exception messages into the log" do
    klass = Class.new(SolidusMcp::Tool) do
      tool_name :audited_failure
      description "Test custom tool"
      category "Test"
      permission "audited_failure"
      read_only true
      ability :read, "Spree::Product"

      protected

      def call
        raise SolidusMcp::ToolError, "PRIVATE-GATEWAY-CREDENTIAL"
      end
    end
    stub_const("AuditedFailure", klass)
    SolidusMcp.configuration.custom_tools = ["AuditedFailure"]
    SolidusMcp.rebuild_registry!
    @saved.update!(permissions: ["audited_failure"])
    expect { execute("audited_failure") }.to raise_error(SolidusMcp::ToolError)
    event = SolidusMcp::ActivityEvent.last
    expect(event).to have_attributes(tool_name: "audited_failure", status: "failed", action: "read")
    expect(event.attributes.to_json).not_to include("PRIVATE-GATEWAY-CREDENTIAL")
  end

  it "fails before tool effects when an initial audit cannot be stored" do
    product
    allow(SolidusMcp::ActivityEvent).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect { execute("update_product", product_id: product.id, changes: {name: "Changed"}) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    expect(product.reload.name).to eq("Test product")
  end

  it "leaves unfinished evidence without turning a completed write into a failed response" do
    allow_any_instance_of(SolidusMcp::ActivityEvent).to receive(:finish!).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect(execute("update_product", product_id: product.id, changes: {name: "Changed"})).to include(updated: true)
    expect(product.reload.name).to eq("Changed")
    expect(SolidusMcp::ActivityEvent.last.status).to eq("started")
  end

  it "leaves interrupted invocations unfinished and clears thread context" do
    allow_any_instance_of(SolidusMcp::Serializers).to receive(:product).and_raise(Interrupt)
    expect { execute("get_product", product_id: product.id) }.to raise_error(Interrupt)
    expect(SolidusMcp::ActivityEvent.last).to have_attributes(status: "started", finished_at: nil)
    expect(SolidusMcp::AuditContext.invocation).to be_nil
  end

  it "does not allow model edits, deletion, or overwriting a completed outcome" do
    execute("get_product", product_id: product.id)
    event = SolidusMcp::ActivityEvent.last
    expect { event.update!(tool_name: "forged") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(event.finish!(status: "failed", duration_ms: 1)).to eq(0)
    expect(event.reload.status).to eq("succeeded")
  end

  it "captures schema failures and hidden tools at the SDK boundary once per request" do
    server = SolidusMcp::Server.build(credential: credential)
    call = ->(name, args) { server.handle_json({jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: name, arguments: args}}.to_json) }
    expect { call.call("get_product", {product_id: product.id}) }.to change(SolidusMcp::ActivityEvent, :count).by(1)
    expect { call.call("get_product", {product_id: 0}) }.to change(SolidusMcp::ActivityEvent, :count).by(1)
    expect(SolidusMcp::ActivityEvent.last.status).to eq("failed")
    @saved.update!(permissions: [])
    expect { call.call("get_product", {product_id: product.id}) }.to change(SolidusMcp::ActivityEvent, :count).by(1)
    expect(SolidusMcp::ActivityEvent.last.status).to eq("denied")
    expect { call.call("NONREGISTERED-PRIVATE-NAME", {}) }.to change(SolidusMcp::ActivityEvent, :count).by(1)
    expect(SolidusMcp::ActivityEvent.last.tool_name).to eq("[unknown tool]")
    expect(SolidusMcp::ActivityEvent.last.attributes.to_json).not_to include("NONREGISTERED-PRIVATE-NAME")
  end

  it "preserves custom protocol results that are arrays rather than objects" do
    server = SolidusMcp::Server.build(credential: credential)
    server.define_custom_method(method_name: "custom/health") { [1, 2] }
    result = JSON.parse(server.handle_json({jsonrpc: "2.0", id: 1, method: "custom/health", params: {}}.to_json))
    expect(result["result"]).to eq([1, 2])
    expect(SolidusMcp::ActivityEvent.last.status).to eq("succeeded")
  end

  it "records discovery without retaining its tool response or initialization input" do
    server = SolidusMcp::Server.build(credential: credential)
    server.handle_json({jsonrpc: "2.0", id: 1, method: "tools/list"}.to_json)
    expect(SolidusMcp::ActivityEvent.last).to have_attributes(protocol_method: "tools/list", tool_name: nil, action: "read", status: "succeeded")
  end
end
