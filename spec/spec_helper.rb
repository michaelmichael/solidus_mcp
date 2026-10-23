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
    SolidusMcp.registry = TestCatalog.registry
    SolidusMcp.default_permissions = []
  end
  config.after do
    SolidusMcp.registry = SolidusMcp::Registry.new
    SolidusMcp.default_permissions = []
  end
end
