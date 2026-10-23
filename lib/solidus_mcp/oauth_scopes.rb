# frozen_string_literal: true

module SolidusMcp
  # One-way, server-owned scope implications. Narrow legacy grants never
  # acquire broader consent. Entries are explicit (not inferred from tools).
  module OauthScopes
    def self.expand(scopes)
      granted = Array(scopes).flat_map { |scope| scope.to_s.split }.uniq
      pending = granted.dup
      until pending.empty?
        Array(SolidusMcp.scope_implications[pending.shift]).each do |scope|
          next if granted.include?(scope)
          granted << scope
          pending << scope
        end
      end
      granted
    end

    def self.permits?(scopes, required)
      expand(scopes).include?(required.to_s)
    end
  end
end
