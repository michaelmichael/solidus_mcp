# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Administrator do
  let(:superadmin) { create_user }
  let(:user) { create_user(mcp_admin: false) }
  let(:assignment) { described_class.new(user: user) }

  it "audits grants and revocations atomically" do
    assignment.change!(actor: superadmin, enabled: true, lock_version: -1)
    expect(SolidusMcp::Administration.role(user)).to eq(:admin)
    expect(assignment.role_changes.last.attributes.slice("actor_id", "previous_enabled", "enabled"))
      .to eq("actor_id" => superadmin.id, "previous_enabled" => false, "enabled" => true)
    assignment.change!(actor: superadmin, enabled: false, lock_version: assignment.lock_version)
    expect(SolidusMcp::Administration.role(user)).to eq(:user)
    expect(assignment.role_changes.count).to eq(2)
  end

  it "denies self-promotion and delegation by ordinary MCP administrators" do
    [user, create_user(superadmin: false)].each do |actor|
      expect {
        assignment.change!(actor: actor, enabled: true, lock_version: -1)
      }.to raise_error(SolidusMcp::AccessDenied)
    end
    expect(assignment).not_to be_persisted
  end

  it "does not let application assignments change superadministrator status" do
    candidate = described_class.new(user: superadmin)
    expect {
      candidate.change!(actor: create_user, enabled: false, lock_version: -1)
    }.to raise_error(SolidusMcp::AccessDenied, /server configuration/)
    expect(SolidusMcp::Administration.superadmin?(superadmin)).to be(true)
  end

  it "rejects duplicate assignments and stale writes" do
    assignment.change!(actor: superadmin, enabled: true, lock_version: -1)
    expect {
      described_class.new(user: user).change!(actor: superadmin, enabled: true, lock_version: -1)
    }.to raise_error(ActiveRecord::RecordInvalid)
    assignment.change!(actor: superadmin, enabled: false, lock_version: assignment.lock_version)
    expect {
      assignment.change!(actor: superadmin, enabled: true, lock_version: 0)
    }.to raise_error(ActiveRecord::StaleObjectError)
    expect(assignment.reload).not_to be_enabled
  end

  it "retains the previous assignment if the audit cannot be saved" do
    assignment.change!(actor: superadmin, enabled: true, lock_version: -1)
    allow_any_instance_of(SolidusMcp::AdministratorChange).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(SolidusMcp::AdministratorChange.new))
    expect {
      assignment.change!(actor: superadmin, enabled: false, lock_version: assignment.lock_version)
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(assignment.reload).to be_enabled
    expect(assignment.role_changes.count).to eq(1)
  end

  it "refuses a role for a non-admin Solidus user" do
    user.update!(admin: false)
    expect {
      assignment.change!(actor: superadmin, enabled: true, lock_version: -1)
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(assignment).not_to be_persisted
  end
end
