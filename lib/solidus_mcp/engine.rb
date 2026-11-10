# frozen_string_literal: true

module SolidusMcp
  class Engine < Rails::Engine
    engine_name "solidus_mcp"

    config.to_prepare do
      SolidusMcp.configuration.validate_serializers!
      SolidusMcp.rebuild_registry!
    end

    initializer "solidus_mcp.filter_credentials" do |app|
      app.config.filter_parameters += %i[access_token refresh_token client_secret code code_verifier authorization]
    end

    initializer "solidus_mcp.stylesheets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.precompile += %w[solidus_mcp/admin.css solidus_mcp/consent.css]
      end
    end

    initializer "solidus_mcp.admin_menu" do |app|
      if defined?(SolidusAdmin::Engine)
        SolidusAdmin::Config.menu_items << {
          key: :mcp_connections, route: :mcp_connections_path, icon: "links-line", position: 85,
          match_path: ->(fullpath) { fullpath.split("?", 2).first.match?(%r{/mcp_(?:connections|administrators)(?:/|$)}) }
        }
      else
        Rails.autoloaders.main.ignore(root.join("app/controllers/solidus_admin"))
      end
    end
  end
end
