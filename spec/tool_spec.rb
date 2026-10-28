# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Custom tools and gem upgrades" do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { SolidusMcp::Credential.new(token, user) }

  def custom_class
    Class.new(SolidusMcp::Tool) do
      tool_name :custom_lookup
      description "A store-specific lookup"
      category "Custom"
      permission "custom_lookup"
      read_only true
      ability :read, "Spree::Product"

      protected

      def call
        {custom: true}
      end
    end
  end

  it "adds a custom tool without replacing built-ins and uses the same authorization" do
    original_tools = SolidusMcp.registry.tools.keys
    stub_const("StoreLookup", custom_class)
    SolidusMcp.configuration.custom_tools = ["StoreLookup"]
    SolidusMcp.rebuild_registry!
    expected_tools = original_tools + ["custom_lookup"]
    expect(SolidusMcp.registry.tools.keys).to match_array(expected_tools)
    expect { StoreLookup.execute(credential: credential) }.to raise_error(SolidusMcp::AccessDenied)
    grant(application: application, user: user, permissions: ["custom_lookup"])
    expect(StoreLookup.execute(credential: credential)).to eq(custom: true)
    expect { StoreLookup.new(credential, SolidusMcp::Policy.new(credential)).call }.to raise_error(NoMethodError)
  end

  it "introduces a standard tool without host changes or inherited grants" do
    saved = grant(application: application, user: user)
    old_grants = saved.permissions.dup
    stub_const("NewStandardLookup", custom_class)
    stub_const("SolidusMcp::BUILTIN_TOOLS", SolidusMcp::BUILTIN_TOOLS + ["NewStandardLookup"])
    SolidusMcp.rebuild_registry!
    expect(SolidusMcp.registry.tools).to have_key("custom_lookup")
    expect(saved.reload.permissions).to eq(old_grants)
    expect { NewStandardLookup.execute(credential: credential) }.to raise_error(SolidusMcp::AccessDenied)
    saved.change!(actor: user, permissions: old_grants + ["custom_lookup"], enabled: true, lock_version: saved.lock_version)
    expect(NewStandardLookup.execute(credential: credential)).to eq(custom: true)
  end

  it "preserves removed permission history without allowing it to execute" do
    saved = grant(application: application, user: user, permissions: ["get_product"])
    catalog = SolidusMcp::Registry.new
    catalog.register SolidusMcp::Tools::SearchProducts
    SolidusMcp.registry = catalog.seal!
    saved.change!(actor: user, permissions: ["get_product"], enabled: false, lock_version: saved.lock_version)
    expect(saved.policy_changes.last.previous_values["permissions"]).to eq(["get_product"])
    expect(SolidusMcp.registry.tools).not_to have_key("get_product")
  end
end
