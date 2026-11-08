# frozen_string_literal: true

class TestUser < ActiveRecord::Base
  def spree_roles
    names = []
    names << "admin" if admin?
    names << "mcp_admin" if mcp_admin?
    names.map { |name| Struct.new(:name).new(name) }
  end
end
