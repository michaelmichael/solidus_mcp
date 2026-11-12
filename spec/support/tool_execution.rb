# frozen_string_literal: true

RSpec.shared_context "tool execution" do
  let(:user) { create_user }
  let(:application) { create_application }
  let(:token) { create_token(application: application, user: user) }
  let(:credential) { SolidusMcp::Credential.new(token, user) }
  let(:product) { create_product }
  before { @saved = grant(application: application, user: user) }

  def execute(name, **arguments)
    SolidusMcp.registry.tools.fetch(name).class_name.constantize.execute(credential: credential, **arguments)
  end
end
