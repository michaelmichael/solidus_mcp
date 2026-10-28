# frozen_string_literal: true

require_relative "boot"
require "rails/all"
Bundler.require(:default)

# This is a test fixture, never a deployable store or authentication example.
raise "The dummy application only runs in test or explicit loading checks" unless ENV["RAILS_ENV"] == "test" || ENV["MCP_LOADING_CHECK"] == "1"

module McpTestHost
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 8.0
    # Keep rate-limit counters local to this test process, including across Docker runs.
    config.cache_store = :memory_store
    config.eager_load = ENV["MCP_EAGER_LOAD"] == "1"
    config.enable_reloading = ENV["MCP_RELOADING"] == "1"
    config.secret_key_base = "solidus-mcp-test-only-" * 8
    config.hosts.clear
    config.action_controller.allow_forgery_protection = true
    config.action_dispatch.show_exceptions = :rescuable
    config.active_support.deprecation = :stderr
    config.active_storage.service = :test
    config.active_job.queue_adapter = :test
    config.action_mailer.delivery_method = :test
    config.logger = ActiveSupport::Logger.new(config.root.join("log/test.log").tap { |p| FileUtils.mkdir_p(p.dirname) })
    config.paths["db/migrate"] << Spree::Core::Engine.root.join("db/migrate").to_s
    config.paths["db/migrate"] << SolidusMcp::Engine.root.join("db/migrate").to_s
  end
end
