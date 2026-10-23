# frozen_string_literal: true

# Only the host contracts used by this engine; no store schema or production data.
class CreateTestHost < ActiveRecord::Migration[8.0]
  def change
    create_table :test_users do |t|
      t.string :email, null: false
      t.boolean :admin, default: false, null: false
    end
    create_table :catalog_entries do |t|
      t.string :name, null: false
      t.boolean :published, default: false, null: false
    end
    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.boolean :confidential, default: true, null: false
      t.timestamps null: false
    end
    add_index :oauth_applications, :uid, unique: true
    create_table :oauth_access_tokens do |t|
      t.bigint :resource_owner_id
      t.references :application, foreign_key: {to_table: :oauth_applications}
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.datetime :revoked_at
      t.datetime :created_at, null: false
      t.string :scopes
      t.string :previous_refresh_token, null: false, default: ""
    end
    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
    create_table :oauth_access_grants do |t|
      t.bigint :resource_owner_id, null: false
      t.references :application, null: false, foreign_key: {to_table: :oauth_applications}
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :scopes
    end
    add_index :oauth_access_grants, :token, unique: true
  end
end
