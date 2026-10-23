# frozen_string_literal: true

Spree.user_class = "TestUser"
Doorkeeper.configure do
  orm :active_record
  resource_owner_authenticator { nil }
  default_scopes :"catalog:read"
  optional_scopes :"products:write"
end

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
