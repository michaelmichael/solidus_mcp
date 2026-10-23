# frozen_string_literal: true

module TestCatalog
  Credential = Struct.new(:token, :user) do
    def active?
      token.reload.accessible?
    end

    def permits?(scope)
      token.scopes.include?(scope)
    end
  end

  class Operations
    def initialize(credential)
      @policy = SolidusMcp::Policy.new(credential)
    end

    def read_entry(id:)
      @policy.authorize!(SolidusMcp.registry.tools.fetch("read_entry"))
      record = @policy.scope(CatalogEntry).find(id)
      @policy.authorize_record!(:read, record)
      {id: record.id, name: record.name}
    end

    def publish_entry(id:)
      @policy.authorize!(SolidusMcp.registry.tools.fetch("publish_entry"))
      record = @policy.scope(CatalogEntry, :update).find(id)
      record.assign_attributes(published: true)
      @policy.authorize_record!(:update, record)
      record.save!
      {id: record.id, published: record.published}
    end
  end

  def self.registry
    registry = SolidusMcp::Registry.new
    registry.resource :entries, model: "CatalogEntry", label: "Catalog entries", actions: {read: :read, publish: :update}
    {read_entry: ["read", "catalog:read"], publish_entry: ["publish", "products:write"]}.each do |name, (permission, scope)|
      registry.tool name, resource: :entries, permissions: ["entries.#{permission}"], handler: "TestCatalog::Operations",
        definition: {scope: scope, description: "#{permission.capitalize} a catalog entry", read_only: permission == "read",
                     properties: {id: {type: "integer"}}, required: ["id"]}
    end
    registry.seal!
  end

  module Helpers
    def create_user(admin: true)
      TestUser.create!(email: "user-#{SecureRandom.hex(4)}@example.test", admin: admin)
    end

    def create_application
      Doorkeeper::Application.create!(name: "Catalog assistant", redirect_uri: "https://client.example/callback", confidential: false)
    end

    def create_token(application:, user:, scopes: "catalog:read products:write")
      Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: scopes, expires_in: 3600)
    end

    def grant(application:, user:, permissions: ["entries.read", "entries.publish"], enabled: true)
      SolidusMcp::ConnectionPolicy.create!(application: application, user: user, permissions: permissions, enabled: enabled)
    end
  end
end
