# frozen_string_literal: true

module SolidusMcp
  # RFC 7591 registration creates a client, never a grant or an access token.
  # Doorkeeper still handles admin consent, PKCE and all token operations.
  class ClientRegistration
    class InvalidMetadata < StandardError
      attr_reader :code

      def initialize(message, code: "invalid_client_metadata")
        @code = code
        super(message)
      end
    end

    def self.call(metadata)
      new(metadata).call
    end

    def initialize(metadata)
      @metadata = metadata
    end

    def call
      invalid!("Expected a JSON object") unless @metadata.is_a?(Hash)
      redirects = redirect_uris
      name = @metadata.fetch("client_name", "MCP client")
      unless name.is_a?(String) && name.strip.present? && name.length <= 128 && !name.match?(/[[:cntrl:]]/)
        invalid!("client_name must be a nonempty string of at most 128 characters")
      end
      auth_method = @metadata.fetch("token_endpoint_auth_method", "client_secret_basic")
      unless %w[none client_secret_basic client_secret_post].include?(auth_method)
        invalid!("Unsupported token_endpoint_auth_method")
      end
      grants = @metadata.fetch("grant_types", ["authorization_code"])
      unless grants.is_a?(Array) && grants.include?("authorization_code") && (grants - %w[authorization_code refresh_token]).empty?
        invalid!("Only authorization_code and refresh_token grants are supported")
      end
      invalid!("Only the code response type is supported") unless @metadata.fetch("response_types", ["code"]) == ["code"]
      application_type = @metadata["application_type"]
      if @metadata.key?("application_type") && !%w[native web].include?(application_type)
        invalid!("application_type must be native or web")
      end
      if application_type == "web" && redirects.any? { |value| URI(value).scheme != "https" }
        invalid!("Web clients require HTTPS callbacks", code: "invalid_redirect_uri")
      end
      scope = @metadata.fetch("scope", Credential::SCOPES.join(" "))
      unless scope.is_a?(String) && scope.split.present? && (scope.split - Credential::SCOPES).empty?
        invalid!("scope must contain only supported store scopes")
      end

      # Select fields explicitly. Caller-supplied IDs, secrets and privileged
      # model attributes are never assigned, and metadata URLs are never fetched.
      client = Doorkeeper::Application.create!(name: name.strip, redirect_uri: redirects,
        confidential: auth_method != "none", scopes: scope.split.uniq.join(" "))
      result = {client_id: client.uid, client_id_issued_at: client.created_at.to_i,
                client_name: client.name, redirect_uris: redirects,
                token_endpoint_auth_method: auth_method, grant_types: grants.uniq,
                response_types: ["code"], scope: client.scopes.to_s}
      result[:application_type] = application_type if application_type
      if client.confidential?
        result[:client_secret] = client.plaintext_secret
        result[:client_secret_expires_at] = 0
      end
      result
    end

    private

    def redirect_uris
      values = @metadata["redirect_uris"]
      unless values.is_a?(Array) && values.length.between?(1, 10) && values.all? { |value| valid_redirect?(value) }
        invalid!("Provide 1 to 10 HTTPS or literal loopback HTTP callback URLs without credentials, fragments or wildcards",
          code: "invalid_redirect_uri")
      end
      values.uniq
    end

    def valid_redirect?(value)
      return false unless value.is_a?(String) && value.bytesize.between?(1, 2048)
      return false if value.match?(/[[:space:][:cntrl:]*\\]/)

      uri = URI.parse(value)
      uri.host.present? && uri.userinfo.nil? && uri.fragment.nil? &&
        (uri.scheme == "https" || (uri.scheme == "http" && %w[127.0.0.1 ::1].include?(uri.hostname)))
    rescue URI::InvalidURIError
      false
    end

    def invalid!(message, code: "invalid_client_metadata")
      raise InvalidMetadata.new(message, code: code)
    end
  end
end
