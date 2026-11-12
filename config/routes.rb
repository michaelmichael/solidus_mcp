# frozen_string_literal: true

if defined?(SolidusAdmin::Engine)
  SolidusAdmin::Engine.routes.draw do
    resources :mcp_administrators, only: [:index, :create, :update] do
      get :search, on: :collection
    end
    resources :mcp_activity, only: [:index]
    resources :mcp_connections, only: [:index]
    get "mcp_connections/:id/owners/:user_id/edit", to: "mcp_connections#edit", as: :edit_mcp_connection
    patch "mcp_connections/:id/owners/:user_id", to: "mcp_connections#update", as: :mcp_connection
    delete "mcp_connections/:id/owners/:user_id", to: "mcp_connections#destroy"

    # Preserve links and forms from the earlier owner path.
    get "mcp_connections/:id/users/:user_id/edit", to: "mcp_connections#edit", defaults: {legacy_owner_path: true}
    patch "mcp_connections/:id/users/:user_id", to: "mcp_connections#update"
    delete "mcp_connections/:id/users/:user_id", to: "mcp_connections#destroy"

    # Existing bookmarks and open forms may still carry the user in the query string.
    resources :mcp_connections, only: [:edit, :update, :destroy], as: :legacy_mcp_connections
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
