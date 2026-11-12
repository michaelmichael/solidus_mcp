# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::RefundPayment do
  include_context "external tool execution"
  let(:method) { Spree::PaymentMethod::Check.create!(name: "Check") }
  let(:payment) { Spree::Payment.create!(order: order, payment_method: method, amount: "20", state: "completed") }
  let(:reason) { Spree::RefundReason.create!(name: "Customer request") }
  let(:arguments) { {payment_id: payment.id, refund_reason_id: reason.id, currency: "USD", amount: "5.00", idempotency_key: "refund-1"} }
  include_examples "a dedicated pending tool", "refund_payment", -> { arguments }

  def refund(**overrides)
    execute("refund_payment", **arguments.merge(overrides))
  end

  it "performs a partial refund and returns the original result without refunding twice" do
    first = refund
    expect(first).to include(payment_id: payment.id, amount: "5.0", currency: "USD", refunded: true)
    expect(first.keys).to match_array(%i[refund_id payment_id amount currency refunded])
    expect { expect(refund).to eq(first) }.not_to change(Spree::Refund, :count)
    expect(payment.reload.credit_allowed).to eq(BigDecimal(15))
    expect { refund(amount: "6.00") }.to raise_error(SolidusMcp::ToolError, /different inputs/)
  end

  it "rejects over-refunds, wrong currency, and invalid decimal amounts before gateway work" do
    expect { refund(amount: "21") }.to raise_error(SolidusMcp::ToolError, /not refundable/)
    expect(Spree::Refund.count).to eq(0)
    expect { refund(currency: "EUR") }.to raise_error(SolidusMcp::ToolError, /Currency/)
    %w[0 -1 1.001 NaN].each { |amount| expect { refund(amount: amount) }.to raise_error(SolidusMcp::ToolError) }
    expect { refund(amount: 1) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "requires payment, order, reason, and new refund authorization" do
    restrict { |ability| ability.cannot :create, Spree::Refund, payment_id: payment.id }
    expect { refund }.to raise_error(SolidusMcp::AccessDenied)
    expect(Spree::Refund.count).to eq(0)
  end

  it "marks gateway failures uncertain and blocks the same key and different keys" do
    payment
    allow_any_instance_of(Spree::PaymentMethod::Check).to receive(:credit).and_raise(Spree::Core::GatewayError, "private gateway data")
    expect { refund }.to raise_error(SolidusMcp::ToolError, /reconcile/)
    expect(SolidusMcp::ToolRequest.last.status).to eq("uncertain")
    expect(Spree::Refund.count).to eq(0)
    expect { refund }.to raise_error(SolidusMcp::ToolError, /reconciliation/)
    expect { refund(idempotency_key: "refund-2") }.to raise_error(SolidusMcp::ToolError, /unresolved/)
  end

  it "blocks repeat gateway work if saving the result fails after gateway success" do
    calls = 0
    allow_any_instance_of(Spree::PaymentMethod::Check).to receive(:credit).and_wrap_original do |original, *args|
      calls += 1
      original.call(*args)
    end
    allow_any_instance_of(SolidusMcp::ToolRequest).to receive(:update!).and_wrap_original do |original, **attrs|
      raise IOError, "simulated persistence failure" if attrs[:status] == "succeeded"
      original.call(**attrs)
    end
    expect { refund }.to raise_error(SolidusMcp::ToolError, /reconcile/)
    expect { refund }.to raise_error(SolidusMcp::ToolError, /reconciliation/)
    expect(calls).to eq(1)
  end

  it "rejects enclosing transactions so claims cannot roll back with gateway work" do
    arguments
    ActiveRecord::Base.transaction do
      expect { refund }.to raise_error(SolidusMcp::ToolError, /enclosing/)
    end
  end
end
