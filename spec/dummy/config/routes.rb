# frozen_string_literal: true

Rails.application.routes.draw do
  mount SolidusAdmin::Engine => "/admin" if defined?(SolidusAdmin::Engine)
  mount Spree::Core::Engine => "/"
end
