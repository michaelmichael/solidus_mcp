# frozen_string_literal: true

Rails.application.routes.draw do
  mount SolidusAdmin::Engine => "/admin" if defined?(SolidusAdmin::Engine)
  mount SolidusMcp::Engine => "/mcp"
  get "/.well-known/oauth-authorization-server", to: "solidus_mcp/metadata#authorization_server"
  get "/.well-known/oauth-protected-resource/mcp", to: "solidus_mcp/metadata#resource"
  mount Spree::Core::Engine => "/"
end
