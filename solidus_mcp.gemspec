# frozen_string_literal: true

require_relative "lib/solidus_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "solidus_mcp"
  spec.version = SolidusMcp::VERSION
  spec.authors = ["Michael Caviness"]
  spec.summary = "Self-contained MCP administration for Solidus stores"
  spec.description = "Standard store tools, OAuth transport, explicit connection permissions and optional SolidusAdmin controls."
  spec.homepage = "https://github.com/michaelmichael/solidus_mcp"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md"
  }
  spec.license = "BSD-3-Clause"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir.chdir(__dir__) { Dir["{app,config,db,lib}/**/*", "README.md", "CHANGELOG.md", "LICENSE"].select { |path| File.file?(path) } }
  spec.require_paths = ["lib"]
  spec.add_dependency "solidus_core", "~> 4.7.0"
  spec.add_dependency "mcp", "~> 1.8.1"
  spec.add_dependency "doorkeeper", "~> 5.9"
end
