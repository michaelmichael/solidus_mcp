# frozen_string_literal: true

if defined?(SolidusAdmin::Engine)
  SolidusAdmin::Engine.routes.draw do
    resources :mcp_connections, only: [:index, :edit, :update, :destroy]
  end
end

SolidusMcp::Engine.routes.draw do
  match "/", to: "solidus_mcp/endpoint#handle", via: [:get, :post, :delete]
  options "/", to: "solidus_mcp/endpoint#preflight"
  get "/metadata", to: "solidus_mcp/metadata#resource"
  get "/oauth/metadata", to: "solidus_mcp/metadata#authorization_server"
  post "/oauth/register", to: "solidus_mcp/registrations#create"
  options "/oauth/*path", to: "solidus_mcp/metadata#preflight"
  use_doorkeeper scope: "oauth" do
    controllers authorizations: "solidus_mcp/authorizations", tokens: "solidus_mcp/tokens"
    skip_controllers :applications, :authorized_applications
  end
end
