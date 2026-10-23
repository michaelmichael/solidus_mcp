# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  private

  # Test-only identity injection. The dummy app refuses to boot outside test.
  def current_test_user
    @current_test_user ||= TestUser.find_by(id: request.headers["X-Test-User"])
  end

  def authenticate_test_user!
    head :unauthorized unless current_test_user
  end
end
