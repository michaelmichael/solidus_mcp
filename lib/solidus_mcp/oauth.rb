# frozen_string_literal: true

module SolidusMcp
  module Oauth
    # Called explicitly once by the installer/host. Doorkeeper is application-wide;
    # never replace an application's existing configuration during engine boot.
    def self.configure!
      Doorkeeper.configure do
        orm :active_record
        resource_owner_authenticator do
          hook = SolidusMcp.configuration.resource_owner_authenticator
          user = if hook
            instance_exec(&hook)
          else
            request.env["warden"]&.authenticate(scope: :spree_user)
          end
          if user
            if user.admin?
              user
            else
              head :forbidden
              nil
            end
          elsif !performed?
            session[:spree_user_return_to] = request.fullpath
            redirect_to "/admin/login"
            nil
          end
        end
        grant_flows %w[authorization_code]
        default_scopes :"mcp:read"
        optional_scopes :"mcp:write"
        enforce_configured_scopes
        access_token_expires_in 1.hour
        use_refresh_token
        force_pkce
        force_ssl_in_redirect_uri { |uri| !%w[127.0.0.1 ::1].include?(uri.hostname) }
        hash_token_secrets
        hash_application_secrets
        custom_access_token_attributes [:resource]
      end
    end
  end
end
