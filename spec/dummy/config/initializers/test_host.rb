# frozen_string_literal: true

Spree.user_class = "TestUser"
SolidusMcp.configure do |config|
  config.custom_tools = ["LoadingProbe"] if ENV["MCP_LOADING_CHECK"] == "1"
  config.endpoint_url = "https://www.example.com/mcp"
  config.issuer_url = "https://www.example.com"
  config.resource_owner_authenticator = -> { TestUser.find_by(id: request.headers["X-Test-User"]) }
end
SolidusMcp::Oauth.configure!

Rails.application.config.to_prepare do
  # Customer permissions query store orders; this host only has fixture models.
  Spree::Config.roles.roles["default"].permission_sets.clear
  if defined?(SolidusAdmin::Engine)
    SolidusAdmin::Config.authentication_method = :authenticate_test_user!
    SolidusAdmin::Config.current_user_method = :current_test_user
    # Exercise the real controller and views without the store-wide admin chrome.
    SolidusAdmin::McpConnectionsController.class_eval do
      def set_layout
        false
      end
    end
  end
end
