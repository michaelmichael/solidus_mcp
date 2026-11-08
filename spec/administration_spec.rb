# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusMcp::Administration do
  let(:superadmin) { create_user }
  let(:administrator) { create_user(superadmin: false) }
  let(:user) { create_user(mcp_admin: false) }
  let(:application) { create_application }
  let(:connection) { grant(application: application, user: user, permissions: ["get_product"]) }

  it "distinguishes environment-designated superadmins, assigned admins and ordinary users" do
    expect(described_class.role(superadmin)).to eq(:superadmin)
    expect(described_class.role(administrator)).to eq(:admin)
    expect(described_class.role(user)).to eq(:user)
    expect(described_class.role(nil)).to be_nil
  end

  it "does not let configuration or an assignment bypass the Solidus admin requirement" do
    outsider = create_user(admin: false)
    expect(described_class.role(outsider)).to be_nil
    SolidusMcp::Administrator.create!(user: outsider)
    expect(described_class.administrator?(outsider)).to be(false)
  end

  it "ignores a freely editable Solidus mcp_admin role" do
    user.update!(mcp_admin: true)
    expect(user.spree_roles.map(&:name)).to include("mcp_admin")
    expect(described_class.role(user)).to eq(:user)
    expect(described_class.administrator?(user)).to be(false)
  end

  it "has no automatic superadmins when none are configured" do
    candidate = superadmin
    SolidusMcp.configuration.superadmin_emails = []
    expect(described_class.role(candidate)).to eq(:user)
  end

  it "limits ordinary administrators to unprivileged users' connections" do
    expect(described_class.can_manage?(administrator, user)).to be(true)
    expect(described_class.can_manage?(administrator, administrator)).to be(false)
    expect(described_class.can_manage?(administrator, superadmin)).to be(false)
    expect(described_class.can_manage?(administrator, create_user(superadmin: false))).to be(false)
    expect(described_class.can_manage?(superadmin, administrator)).to be(true)
    expect(described_class.can_manage?(superadmin, superadmin)).to be(true)
    expect(described_class.can_manage?(user, user)).to be(false)
  end

  it "prevents MCP users from changing, deleting or restoring their own grants through Ruby" do
    saved = connection
    expect {
      saved.change!(actor: user, permissions: ["update_product"], enabled: true, lock_version: saved.lock_version)
    }.to raise_error(SolidusMcp::AccessDenied)
    expect {
      saved.delete_permissions!(actor: user, lock_version: saved.lock_version)
    }.to raise_error(SolidusMcp::AccessDenied)
    saved.delete_permissions!(actor: administrator, lock_version: saved.lock_version)
    expect {
      saved.change!(actor: user, permissions: ["update_product"], enabled: true, lock_version: saved.lock_version)
    }.to raise_error(SolidusMcp::AccessDenied)
    expect(saved.reload.permissions).to eq([])
    expect(saved).not_to be_enabled
    expect(saved.deleted_at).to be_present
    expect(saved.policy_changes.count).to eq(1)
  end

  it "rechecks a revoked assignment even when the caller retains the old actor object" do
    saved = connection
    actor = administrator
    SolidusMcp::Administrator.where(user_id: actor.id).update_all(enabled: false)
    expect {
      saved.change!(actor: actor, permissions: ["update_product"], enabled: true, lock_version: saved.lock_version)
    }.to raise_error(SolidusMcp::AccessDenied)
    expect(saved.reload.permissions).to eq(["get_product"])
    expect(saved.policy_changes.count).to eq(0)
  end

  it "protects a connection immediately after its owner becomes an MCP administrator" do
    saved = connection
    actor = administrator
    SolidusMcp::Administrator.new(user: user).change!(actor: superadmin, enabled: true, lock_version: -1)
    expect {
      saved.change!(actor: actor, permissions: [], enabled: false, lock_version: saved.lock_version)
    }.to raise_error(SolidusMcp::AccessDenied)
    expect(saved.reload.permissions).to eq(["get_product"])
  end

  it "also enforces host Solidus abilities on model-level permission changes" do
    ability = Spree::Ability.new(administrator)
    ability.cannot :manage, :mcp_connections
    allow(Spree::Ability).to receive(:new).with(administrator).and_return(ability)
    expect {
      connection.change!(actor: administrator, permissions: [], enabled: false, lock_version: connection.lock_version)
    }.to raise_error(SolidusMcp::AccessDenied)
    expect(connection.reload.permissions).to eq(["get_product"])
  end

  it "resolves configured login emails without case sensitivity" do
    account = superadmin
    SolidusMcp.configuration.superadmin_emails = [" #{account.email.upcase} "]
    expect(described_class.superadmin?(account)).to be(true)
    expect(described_class.superadmin_user_ids).to eq([account.id.to_s])
  end

  it "fails closed when a configured login email identifies multiple accounts" do
    account = superadmin
    duplicate = create_user(mcp_admin: false)
    duplicate.update!(email: account.email.upcase)
    expect(described_class.superadmin?(account)).to be(false)
    expect(described_class.superadmin?(duplicate)).to be(false)
  end

  it "removes superadministrator access when the account's configured email changes" do
    account = superadmin
    account.update!(email: "changed@example.test")
    expect(described_class.superadmin?(account)).to be(false)
  end

  it "normalizes configured superadmin email addresses and rejects invalid entries" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SOLIDUS_MCP_SUPERADMIN_EMAILS", "").and_return(" Owner@Example.test, Security@example.test ")
    expect(SolidusMcp::Configuration.new.superadmin_emails).to eq(%w[owner@example.test security@example.test])
    allow(ENV).to receive(:fetch).with("SOLIDUS_MCP_SUPERADMIN_EMAILS", "").and_return("1,admin")
    expect { SolidusMcp::Configuration.new }.to raise_error(ArgumentError, /login email addresses/)
  end
end
