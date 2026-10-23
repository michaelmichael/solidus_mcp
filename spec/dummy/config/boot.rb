# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)
ENV["SOLIDUS_SKIP_MIGRATIONS_CHECK"] = "true" # This fixture has no store tables.
require "bundler/setup"
