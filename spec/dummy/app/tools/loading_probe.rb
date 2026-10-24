# frozen_string_literal: true

class LoadingProbe < SolidusMcp::Tool
  tool_name :loading_probe
  description "Test-only custom tool"
  category "Custom"
  permission "loading_probe"
  read_only true
  ability :read, "Spree::Product"

  protected

  def call
    {loaded: true}
  end
end
