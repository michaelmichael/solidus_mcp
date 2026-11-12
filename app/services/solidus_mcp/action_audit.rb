# frozen_string_literal: true

module SolidusMcp
  class ActionAudit
    TARGET_KEYS = %w[product_id variant_id price_id order_id payment_id shipment_id
      taxon_id taxonomy_id option_type_id option_value_id shipping_category_id
      stock_location_id stock_item_id image_id image_ids refund_reason_id refund_id stock_movement_id].freeze
    Invocation = Struct.new(:event, :credential, :tool_name, :claimed, :status, :error_class, :result_ids, keyword_init: true)

    class << self
      def tool(credential:, tool_name:, arguments:)
        invocation = AuditContext.invocation
        if invocation && !invocation.claimed && invocation.tool_name == tool_name && invocation.credential.equal?(credential)
          invocation.claimed = true
          observe(invocation) do
            result = yield
            summarize_result(invocation, result)
            result
          end
        else
          capture(credential: credential, tool_name: tool_name, arguments: arguments, protocol_method: "tools/call") do |current|
            current.claimed = true
            result = yield
            summarize_result(current, result)
            result
          end
        end
      end

      def protocol(credential:, payload:)
        return yield unless payload.is_a?(Hash)
        method = payload[:method] || payload["method"]
        return yield unless method.is_a?(String)
        params = payload[:params] || payload["params"]
        params = {} unless params.is_a?(Hash)
        tool_name = params[:name] || params["name"] if method == "tools/call"
        arguments = params[:arguments] || params["arguments"]
        # Only named protocol operations are retained, never arbitrary client text.
        method = "unknown" unless %w[initialize ping tools/call tools/list resources/list resources/read resources/templates/list prompts/list prompts/get notifications/initialized].include?(method)
        capture(credential: credential, tool_name: tool_name, arguments: arguments, protocol_method: method) do |invocation|
          result = yield
          response = result.is_a?(String) ? JSON.parse(result) : result
          if protocol_method_tool_notification?(method, invocation, response)
            invocation.status = "failed"
            invocation.error_class = "MCP::ProtocolError"
          end
          response_result = response["result"] || response[:result] if response.is_a?(Hash)
          error_result = response_result.is_a?(Hash) && (response_result["isError"] || response_result[:isError])
          if response.is_a?(Hash) && (response.key?("error") || response.key?(:error) || error_result)
            unless invocation.status
              entry = SolidusMcp.registry.tools[tool_name] if tool_name.is_a?(String)
              allowed = entry && Policy.new(credential).allowed?(entry)
              invocation.status = (method == "tools/call" && !allowed) ? "denied" : "failed"
              invocation.error_class = allowed ? "MCP::ProtocolError" : "SolidusMcp::AccessDenied"
            end
          end
          result
        end
      end

      def capture(credential:, tool_name:, arguments:, protocol_method:)
        entry = SolidusMcp.registry.tools[tool_name] if tool_name.is_a?(String)
        args = arguments.is_a?(Hash) ? arguments.stringify_keys : {}
        token = credential.token
        application = token.application
        fields = args["changes"].is_a?(Hash) ? args["changes"].keys.map(&:to_s) : []
        allowed_fields = entry&.input_schema&.dig(:properties, "changes", :properties)&.keys || []
        event = ActivityEvent.create!(event_id: SecureRandom.uuid, request_id: AuditContext.request_id,
          user_id: token.resource_owner_id, actor_role: Administration.role(credential.user)&.to_s || "unknown", application_id: token.application_id, token_id: token.id,
          application_uid: application&.uid, application_name: application&.name&.first(255),
          protocol_method: protocol_method, tool_name: entry&.name || ((protocol_method == "tools/call") ? "[unknown tool]" : nil),
          permission: entry&.permission, category: entry&.category || "Protocol",
          action: entry&.audit_action || ((protocol_method == "tools/call") ? "unknown" : "read"),
          resource_ids: target_ids(args), changed_fields: (fields & allowed_fields.map(&:to_s)).sort,
          started_at: Time.current)
        AuditContext.event_count = AuditContext.event_count.to_i + 1
        invocation = Invocation.new(event: event, credential: credential, tool_name: tool_name, claimed: false)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        previous = AuditContext.invocation
        AuditContext.invocation = invocation
        finished_normally = false
        begin
          result = observe(invocation) { yield invocation }
          finished_normally = true
          result
        ensure
          AuditContext.invocation = previous
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          begin
            if finished_normally || invocation.status
              event.finish!(status: invocation.status || "succeeded", duration_ms: elapsed, error_class: invocation.error_class, result_ids: invocation.result_ids || {})
            end
          rescue
            # The initial record remains visible as unfinished. Do not turn an
            # already-completed mutation into a failure and invite a duplicate retry.
            Rails.logger.error("Solidus MCP could not complete activity event #{event.event_id}")
          end
        end
      end

      private

      def observe(invocation)
        yield
      rescue => error
        invocation.status = error.is_a?(SolidusMcp::AccessDenied) ? "denied" : "failed"
        invocation.error_class = error.class.name.presence || "StandardError"
        raise
      end

      def protocol_method_tool_notification?(method, invocation, response)
        method == "tools/call" && !invocation.claimed && response.nil?
      end

      def summarize_result(invocation, result)
        invocation.result_ids = result_ids(result)
        return unless result.is_a?(Hash)
        batch = result[:results] || result["results"]
        return unless batch.is_a?(Array) && batch.any?
        flags = batch.first(100).map do |item|
          next :unknown unless item.is_a?(Hash)
          value = item.key?(:success) ? item[:success] : item["success"]
          (value == true || value == false) ? value : :unknown
        end
        return unless flags.size == batch.size && !flags.include?(:unknown)
        invocation.status = if flags.all?
          "succeeded"
        else
          (flags.any? ? "partial" : "failed")
        end
      end

      def result_ids(result)
        return {} unless result.is_a?(Hash)
        values = result.stringify_keys
        ids = target_ids(values)
        records = values["items"].is_a?(Array) ? values["items"].first(100) : [values]
        returned = records.filter_map do |record|
          next unless record.is_a?(Hash)
          id = record[:id] || record["id"]
          id if id.is_a?(Integer) && id.positive?
        end
        ids["returned_ids"] = returned unless returned.empty?
        if values["results"].is_a?(Array)
          ids["batch"] = values["results"].first(100).filter_map do |record|
            next unless record.is_a?(Hash)
            item = record.stringify_keys
            next unless [true, false].include?(item["success"])
            references = item["price"].is_a?(Hash) ? target_ids(item["price"].stringify_keys) : {}
            references.merge("success" => item["success"]).tap do |entry|
              entry["index"] = item["index"] if item["index"].is_a?(Integer) && item["index"] >= 0
            end
          end
        end
        ids
      end

      def target_ids(arguments)
        arguments.slice(*TARGET_KEYS).filter_map do |key, value|
          if value.is_a?(Integer) && value.positive?
            [key, value]
          elsif value.is_a?(Array) && value.length <= 100 && value.all? { |id| id.is_a?(Integer) && id.positive? }
            [key, value]
          end
        end.to_h
      end
    end
  end
end
