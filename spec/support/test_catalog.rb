# frozen_string_literal: true

module TestCatalog
  module Helpers
    def create_user(admin: true)
      TestUser.create!(email: "user-#{SecureRandom.hex(4)}@example.test", admin: admin)
    end

    def create_application
      Doorkeeper::Application.create!(name: "Catalog assistant", redirect_uri: "https://client.example/callback", confidential: false, scopes: "mcp:read mcp:write")
    end

    def create_token(application:, user:, scopes: "mcp:read mcp:write")
      Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id,
        scopes: scopes, expires_in: 3600, resource: SolidusMcp.configuration.endpoint_url)
    end

    def grant(application:, user:, permissions: SolidusMcp.registry.permissions, enabled: true)
      SolidusMcp::ConnectionPolicy.create!(application: application, user: user, permissions: permissions, enabled: enabled)
    end

    def create_product(sku: "SKU-1", amount: "12.50")
      shipping = Spree::ShippingCategory.first || Spree::ShippingCategory.create!(name: "Default")
      Spree::Product.create!(name: "Test product", price: amount, sku: sku, shipping_category: shipping)
    end
  end
end
