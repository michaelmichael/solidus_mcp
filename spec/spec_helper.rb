# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "rspec/rails"
require_relative "support/test_catalog"

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.include TestCatalog::Helpers
  config.before do
    SolidusMcp.configuration.product_serializer = nil
    SolidusMcp.configuration.order_serializer = nil
    SolidusMcp.configuration.superadmin_emails = []
    Rails.cache.clear
    SolidusMcp.configuration.custom_tools = []
    SolidusMcp.rebuild_registry!
  end
  config.after do
    SolidusMcp.configuration.product_serializer = nil
    SolidusMcp.configuration.order_serializer = nil
    SolidusMcp.configuration.superadmin_emails = []
    SolidusMcp.configuration.custom_tools = []
    SolidusMcp.rebuild_registry!
  end
end
