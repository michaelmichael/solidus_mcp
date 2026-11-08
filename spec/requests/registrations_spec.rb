# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OAuth registration rate limits", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def register_from(ip)
    post "/mcp/oauth/register", params: "{}",
      headers: {"Content-Type" => "application/json", "REMOTE_ADDR" => ip}
  end

  it "limits each IP independently and permits requests after the window expires" do
    20.times do
      register_from("192.0.2.1")
      expect(response).to have_http_status(:bad_request)
    end
    register_from("192.0.2.1")
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("3600")
    expect(response.parsed_body["error"]).to eq("temporarily_unavailable")

    register_from("192.0.2.2")
    expect(response).to have_http_status(:bad_request)

    travel 1.hour + 1.second do
      register_from("192.0.2.1")
      expect(response).to have_http_status(:bad_request)
    end
  end

  it "also limits total requests across different IPs" do
    200.times do |index|
      register_from("192.0.2.#{index / 20 + 1}")
      expect(response).to have_http_status(:bad_request)
    end
    register_from("192.0.2.11")
    expect(response).to have_http_status(:too_many_requests)
  end
end
