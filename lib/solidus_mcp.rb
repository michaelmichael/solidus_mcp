# frozen_string_literal: true

require "solidus_core"
require "mcp"
require "doorkeeper"
require "solidus_mcp/version"
require "solidus_mcp/configuration"
require "solidus_mcp/oauth"
require "solidus_mcp/tool"
require "solidus_mcp/registry"
require "solidus_mcp/policy"
require "solidus_mcp/connection_scopes"
require "solidus_mcp/server"

module SolidusMcp
  class AccessDenied < StandardError; end

  class ToolError < StandardError; end

  class InsufficientScope < AccessDenied
    attr_reader :scopes

    def initialize(scopes)
      @scopes = scopes
      super("Additional OAuth authorization required: #{scopes.join(" ")}")
    end
  end

  BUILTIN_TOOLS = %w[SearchProducts GetProduct GetProductVariants GetVariantPrices
    UpdateProduct UpdateVariantPrice BulkUpdateVariantPrices GetInventoryLevels
    SearchInventory SearchOrders GetOrder GetOrderStatus].map { |name| "SolidusMcp::Tools::#{name}" }.freeze

  class << self
    attr_writer :registry

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def registry
      @registry ||= Registry.new.seal!
    end

    def rebuild_registry!
      catalog = Registry.new
      (BUILTIN_TOOLS + configuration.custom_tools).each { |name| catalog.register(name.constantize) }
      self.registry = catalog.seal!
    end
  end
end

require "solidus_mcp/engine"
