# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "spec/dummy/config/application"
Rails.application.load_tasks
require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)
task default: :spec
