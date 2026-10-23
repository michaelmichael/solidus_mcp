# frozen_string_literal: true

module SolidusMcp
  # Diagnostic only: never changes a token or substitutes for Policy checks.
  # A single token must contain all scopes; combining different tokens is invalid.
  class ConnectionScopes
    def initialize(scope_sets)
      @scope_sets = scope_sets.map { |scopes| scopes.to_s.split.uniq }
    end

    def warning(tool)
      return "No active access token. Reconnect or refresh; this tool requires #{tool.scopes.join(", ")}." if @scope_sets.empty?

      missing = @scope_sets.map { |scopes| tool.scopes - scopes }
      return if missing.all?(&:empty?)

      scopes = missing.flatten.uniq.sort.join(", ")
      if missing.any?(&:empty?)
        "Some active tokens lack #{scopes}. If this tool is missing in your client, reconnect with those scopes."
      else
        "Requires reconnection with #{scopes}. No active token has all scopes required by this tool."
      end
    end
  end
end
