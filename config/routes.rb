# frozen_string_literal: true

if defined?(SolidusAdmin::Engine)
  SolidusAdmin::Engine.routes.draw do
    resources :mcp_connections, only: [:index, :edit, :update, :destroy]
  end
end
