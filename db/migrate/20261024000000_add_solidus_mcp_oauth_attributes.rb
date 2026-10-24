# frozen_string_literal: true

class AddSolidusMcpOauthAttributes < ActiveRecord::Migration[7.1]
  def up
    %i[oauth_access_tokens oauth_access_grants].each do |table|
      add_column table, :resource, :string unless column_exists?(table, :resource)
    end
    %i[code_challenge code_challenge_method].each do |column|
      add_column :oauth_access_grants, column, :string unless column_exists?(:oauth_access_grants, column)
    end
  end

  def down
    # Columns may predate the engine and be used by other Doorkeeper clients.
    raise ActiveRecord::IrreversibleMigration
  end
end
