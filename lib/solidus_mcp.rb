# frozen_string_literal: true

require "solidus_core"
require "mcp"
require "doorkeeper"
require "solidus_mcp/version"
require "solidus_mcp/tool"
require "solidus_mcp/registry"
require "solidus_mcp/policy"
require "solidus_mcp/connection_scopes"
require "solidus_mcp/server"
require "solidus_mcp/engine"

module SolidusMcp
  class AccessDenied < StandardError; end

  class << self
    attr_writer :registry
    # An explicit compatibility allowlist, never derived from registry contents.
    # New installations default to no grants. A host may opt in existing tools.
    attr_accessor :default_permissions, :reconnect_instructions

    def registry
      @registry ||= Registry.new
    end
  end
  self.default_permissions = [].freeze
end
