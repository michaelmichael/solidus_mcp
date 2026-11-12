# frozen_string_literal: true

module SolidusAdmin
  class McpActivityController < BaseController
    before_action :require_mcp_user

    def index
      @filters = params.permit(:user, :tool, :action_type, :outcome, :from, :to, :before_id).to_h
      events = SolidusMcp::ActivityEvent.visible_to(current_solidus_admin_user)
      if @filters["user"].present?
        value = @filters["user"].first(255)
        if value.match?(/\A[0-9]{1,18}\z/)
          events = events.where(user_id: value.to_i)
        else
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
          events = events.where(user_id: Spree.user_class.where("email ILIKE ?", pattern).select(:id))
        end
      end
      events = events.where(tool_name: @filters["tool"].first(128)) if @filters["tool"].present?
      if @filters["outcome"].present?
        raise ActionController::BadRequest, "Invalid outcome" unless SolidusMcp::ActivityEvent::STATUSES.include?(@filters["outcome"])
        events = events.where(status: @filters["outcome"])
      end
      from = filter_time(@filters["from"])
      to = filter_time(@filters["to"])
      raise ActionController::BadRequest, "Invalid time range" if from && to && from > to
      events = events.where("started_at >= ?", from) if from
      events = events.where("started_at <= ?", to) if to
      @filters["from"] = from.in_time_zone.strftime("%Y-%m-%dT%H:%M:%S") if from
      @filters["to"] = to.in_time_zone.strftime("%Y-%m-%dT%H:%M:%S") if to
      @counts = events.group(:action).count
      if @filters["action_type"].present?
        raise ActionController::BadRequest, "Invalid action type" unless SolidusMcp::ActivityEvent::ACTIONS.include?(@filters["action_type"])
        events = events.where(action: @filters["action_type"])
      end
      if @filters["before_id"].present?
        raise ActionController::BadRequest, "Invalid cursor" unless @filters["before_id"].match?(/\A[1-9][0-9]{0,17}\z/)
        events = events.where("id < ?", @filters["before_id"].to_i)
      end
      @events = events.order(id: :desc).limit(51).to_a
      @more = @events.size > 50
      @events = @events.first(50)
      @users = Spree.user_class.where(id: @events.map(&:user_id)).index_by(&:id)
    end

    private

    def authorization_subject
      :mcp_connections
    end

    def require_mcp_user
      head :forbidden unless SolidusMcp::Administration.user?(current_solidus_admin_user)
    end

    def filter_time(value)
      return if value.blank?
      unless value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?\z/)
        raise ActionController::BadRequest, "Invalid time filter"
      end
      parsed = DateTime.iso8601(value)
      value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/) ? parsed.to_time : Time.zone.local(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second)
    rescue ArgumentError
      raise ActionController::BadRequest, "Invalid time filter"
    end
  end
end
