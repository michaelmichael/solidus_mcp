# frozen_string_literal: true

namespace :solidus_mcp do
  desc "Run engine migrations directly from the installed gem (after host migrations)"
  task migrate: :environment do
    context = ActiveRecord::MigrationContext.new(SolidusMcp::Engine.root.join("db/migrate").to_s)
    context.migrate
  end
end
