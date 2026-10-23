# frozen_string_literal: true

class TestUser < ActiveRecord::Base
  def spree_roles
    admin? ? [Struct.new(:name).new("admin")] : []
  end
end
