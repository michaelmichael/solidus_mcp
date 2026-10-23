# frozen_string_literal: true

module SolidusMcp
  class Engine < Rails::Engine
    engine_name "solidus_mcp"

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
