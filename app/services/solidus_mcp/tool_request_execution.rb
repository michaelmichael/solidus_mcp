# frozen_string_literal: true

module SolidusMcp
  # External effects cannot be undone by a database rollback. Commit the claim
  # before entering the workflow and keep uncertain targets blocked for review.
  class ToolRequestExecution
    def initialize(credential, operation:, key:, payload:)
      unless key.match?(/\A[A-Za-z0-9_.:-]{1,128}\z/)
        raise ToolError, "Invalid idempotency key"
      end
      @connection = ConnectionPolicy.find_by!(application_id: credential.token.application_id, user_id: credential.user.id)
      @operation, @key, @payload = operation, key, payload.deep_stringify_keys
    end

    def database
      ToolRequest.transaction do
        request = find_request
        request.with_lock do
          check_payload!(request)
          return request.result.symbolize_keys if request.status == "succeeded"
          result = yield
          request.update!(status: "succeeded", result: result)
          result
        end
      end
    end

    def external(guard_key:)
      if ToolRequest.connection.transaction_open?
        raise ToolError, "External workflow tools must run outside an enclosing database transaction"
      end
      request = find_request
      replay = nil
      request.with_lock do
        check_payload!(request)
        if request.status == "succeeded"
          replay = request.result.symbolize_keys
        elsif %w[processing uncertain].include?(request.status)
          raise ToolError, "Request #{request.id} requires reconciliation before retry"
        else
          request.update!(status: "processing", guard_key: guard_key)
        end
      end
      return replay if replay

      effects_started = false
      begin
        ToolRequest.transaction do
          result = yield(-> { effects_started = true })
          request.update!(status: "succeeded", result: result)
          result
        end
      rescue
        request.reload.update!(status: effects_started ? "uncertain" : "failed")
        if effects_started
          raise ToolError, "Request #{request.id} may have reached external systems; reconcile before retry. No automatic repeat is allowed."
        end
        raise
      end
    rescue ActiveRecord::RecordNotUnique
      raise ToolError, "Another unresolved operation exists for this order; reconcile it before retry"
    end

    private

    def find_request
      ToolRequest.create_or_find_by!(connection_policy_id: @connection.id, operation: @operation, idempotency_key: @key) do |record|
        record.payload = @payload
      end
    end

    def check_payload!(request)
      raise ToolError, "Idempotency key was already used with different inputs" unless request.payload == @payload
    end
  end
end
