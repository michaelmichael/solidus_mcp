source "https://rubygems.org"

gemspec

gem "rails", "~> 8.0.2"
gem "solidus_core", "~> 4.7.0"
gem "solidus_admin", "~> 0.4.0" unless ENV["WITHOUT_ADMIN"] == "1"
gem "pg", "~> 1.5"
gem "sprockets-rails", "~> 3.5"
gem "rspec-rails", "~> 7.1"
gem "standard", "~> 1.45.0", require: false

# Rails 8.0 passes JSON encoder options removed in JSON 3.
gem "json", "~> 2.10"
