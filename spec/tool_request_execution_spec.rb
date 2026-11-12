# frozen_string_literal: true

require "spec_helper"
require_relative "support/pending_tools"

RSpec.describe SolidusMcp::ToolRequestExecution do
  include_context "external tool execution"

  def request(key: "request-1", operation: "refund_payment")
    described_class.new(credential, operation: operation, key: key, payload: {order_id: order.id})
  end

  it "keeps a committed processing claim visible while an external action is running" do
    request
    started = Queue.new
    release = Queue.new
    worker = Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          request.external(guard_key: "order:#{order.id}") do |effects|
            effects.call
            started << true
            release.pop
            {completed: true}
          end
        end
      end
    end
    Timeout.timeout(10) { started.pop }
    expect(SolidusMcp::ToolRequest.find_by!(idempotency_key: "request-1").status).to eq("processing")
    expect { request(key: "other", operation: "cancel_order").external(guard_key: "order:#{order.id}") { raise "must not run" } }.to raise_error(SolidusMcp::ToolError, /unresolved/)
    expect { request.external(guard_key: "order:#{order.id}") { raise "must not run" } }.to raise_error(SolidusMcp::ToolError, /reconciliation/)
    release << true
    expect(Timeout.timeout(10) { worker.value }).to eq(completed: true)
    expect(request.external(guard_key: "order:#{order.id}") { raise "must not run" }).to eq(completed: true)
  ensure
    worker&.kill if worker&.alive?
    worker&.join
  end

  it "retains an uncertain target across connection/token instances" do
    expect do
      request.external(guard_key: "order:#{order.id}") do |effects|
        effects.call
        raise IOError, "Uncertain remote result"
      end
    end.to raise_error(SolidusMcp::ToolError, /reconcile/)
    expect { request(key: "other", operation: "ship_shipment").external(guard_key: "order:#{order.id}") { raise "must not run" } }.to raise_error(SolidusMcp::ToolError, /unresolved/)
  end
end
