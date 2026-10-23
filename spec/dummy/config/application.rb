# frozen_string_literal: true

require_relative "boot"
require "rails/all"
Bundler.require(:default)

# This is a test fixture, never a deployable store or authentication example.
raise "The dummy application only runs in test" unless ENV["RAILS_ENV"] == "test"

module McpTestHost
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 8.0
    config.eager_load = false
    config.secret_key_base = "solidus-mcp-test-only-" * 8
    config.hosts.clear
    config.action_controller.allow_forgery_protection = true
    config.action_dispatch.show_exceptions = :rescuable
    config.active_support.deprecation = :stderr
    config.active_storage.service = :test
    config.active_job.queue_adapter = :test
    config.action_mailer.delivery_method = :test
    config.logger = ActiveSupport::Logger.new(config.root.join("log/test.log").tap { |p| FileUtils.mkdir_p(p.dirname) })
    config.paths["db/migrate"] << SolidusMcp::Engine.root.join("db/migrate").to_s
  end
end
