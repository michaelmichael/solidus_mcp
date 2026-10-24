# frozen_string_literal: true

module SolidusMcp
  class Engine < Rails::Engine
    engine_name "solidus_mcp"

    config.to_prepare do
      SolidusMcp.rebuild_registry!
    end

    initializer "solidus_mcp.filter_credentials" do |app|
      app.config.filter_parameters += %i[access_token refresh_token client_secret code code_verifier authorization]
    end

    initializer "solidus_mcp.admin_menu" do
      if defined?(SolidusAdmin::Engine)
        SolidusAdmin::Config.menu_items << {
          key: :mcp_connections, route: :mcp_connections_path, icon: "links-line", position: 85
        }
      else
        Rails.autoloaders.main.ignore(root.join("app/controllers/solidus_admin"))
      end
    end
  end
end
