# frozen_string_literal: true

module SolidusAdmin
  class McpConnectionsController < BaseController
    before_action :require_mcp_user
    helper_method :mcp_administrator?, :mcp_superadministrator?, :manage_connection_permissions?, :can_manage_connection?

    rescue_from SolidusMcp::AccessDenied do
      head :forbidden
    end
    before_action :load_connection, only: [:edit, :update, :destroy]
    before_action :require_permission_manager, only: [:update, :destroy]

    def index
      @show_deleted = params[:deleted] == "1"
      @page = [params[:page].to_i, 1].max
      connections = Doorkeeper::AccessToken.where(resource: SolidusMcp.configuration.endpoint_url).where.not(application_id: nil).where.not(resource_owner_id: nil)
      connections = SolidusMcp::Administration.visible_connections(connections, current_solidus_admin_user)
      @connections = connections.where("#{@show_deleted ? "" : "NOT "}EXISTS (SELECT 1 FROM solidus_mcp_connection_policies p WHERE p.application_id = oauth_access_tokens.application_id AND p.user_id = oauth_access_tokens.resource_owner_id AND p.deleted_at IS NOT NULL)")
        .select(:application_id, :resource_owner_id).distinct.order(:application_id, :resource_owner_id)
        .offset((@page - 1) * 25).limit(26).to_a
      @more = @connections.size > 25
      @connections = @connections.first(25)
      @applications = Doorkeeper::Application.where(id: @connections.map(&:application_id)).index_by(&:id)
      @users = Spree.user_class.where(id: @connections.map(&:resource_owner_id)).index_by(&:id)
      @active_connections = Doorkeeper::AccessToken.where(resource: SolidusMcp.configuration.endpoint_url,
        application_id: @applications.keys, resource_owner_id: @users.keys, revoked_at: nil)
        .where("expires_in IS NULL OR created_at + expires_in * interval '1 second' > ?", Time.current)
        .distinct.pluck(:application_id, :resource_owner_id)
      @policies = SolidusMcp::ConnectionPolicy.where(application_id: @applications.keys, user_id: @users.keys)
        .index_by { |policy| [policy.application_id, policy.user_id] }
    end

    def edit
      # GET forms in the admin navigation replace query parameters on submission.
      # Keep the connection owner in the path before rendering those forms.
      if !request.path_parameters.key?(:user_id) || request.path_parameters[:legacy_owner_path]
        redirect_to solidus_admin.edit_mcp_connection_path(@application, user_id: @user.id), status: :see_other
      end
    end

    def update
      submitted = params.require(:connection_policy).permit(:enabled, :lock_version, permissions: [])
      version = submitted[:lock_version]
      raise ActionController::BadRequest, "Missing policy version" unless version.is_a?(String) && version.match?(/\A(?:-1|[0-9]+)\z/)
      raise ActionController::BadRequest, "Invalid connection status" unless %w[0 1].include?(submitted[:enabled])

      @policy.change!(actor: current_solidus_admin_user,
        permissions: submitted.fetch(:permissions, []).reject(&:blank?),
        enabled: submitted[:enabled] == "1", lock_version: version.to_i)
      needs_reconnect = @registry.tools.values.any? do |tool|
        (tool.permissions - @policy.permissions).empty? && @scope_status.warning(tool)
      end
      notice = if @policy.enabled? && needs_reconnect
        "Connection permissions saved. OAuth access is still missing for some tools; follow the reconnect instructions below."
      else
        "Connection permissions saved. They apply to the next request, within the token's OAuth scopes."
      end
      redirect_to solidus_admin.edit_mcp_connection_path(@application, user_id: @user.id), notice: notice, status: :see_other
    rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
      @policy.reload if @policy.persisted?
      flash.now[:error] = "Another administrator changed this connection. Reload the page before saving again."
      render :edit, status: :conflict
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:error] = e.record.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end

    def destroy
      version = params.require(:connection_policy).permit(:lock_version)[:lock_version]
      raise ActionController::BadRequest, "Missing policy version" unless version.is_a?(String) && version.match?(/\A(?:-1|[0-9]+)\z/)
      @policy.delete_permissions!(actor: current_solidus_admin_user, lock_version: version.to_i)
      redirect_to solidus_admin.mcp_connections_path,
        notice: "Permission set deleted. Access is disabled; its audit history is retained under Deleted permission sets.", status: :see_other
    rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
      @policy.reload if @policy.persisted?
      flash.now[:error] = "Another administrator changed this connection. Reload the page before deleting it."
      render :edit, status: :conflict
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:error] = e.record.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end

    private

    def authorization_subject
      :mcp_connections
    end

    def require_mcp_user
      head :forbidden unless SolidusMcp::Administration.user?(current_solidus_admin_user)
    end

    def require_permission_manager
      head :forbidden unless manage_connection_permissions?
    end

    def mcp_administrator?
      @mcp_administrator ||= SolidusMcp::Administration.administrator?(current_solidus_admin_user)
    end

    def mcp_superadministrator?
      SolidusMcp::Administration.superadmin?(current_solidus_admin_user)
    end

    def can_manage_connection?(owner)
      SolidusMcp::Administration.can_manage?(current_solidus_admin_user, owner)
    end

    def manage_connection_permissions?
      @can_manage_permissions
    end

    def load_connection
      @user = Spree.user_class.find(params.require(:user_id))
      unless SolidusMcp::Administration.can_view?(current_solidus_admin_user, @user)
        raise ActiveRecord::RecordNotFound
      end
      @application = Doorkeeper::Application.find(params[:id])
      @can_manage_permissions = can_manage_connection?(@user)
      tokens = Doorkeeper::AccessToken.where(application_id: @application.id, resource_owner_id: @user.id, resource: SolidusMcp.configuration.endpoint_url)
      raise ActiveRecord::RecordNotFound unless tokens.exists?
      scope_sets = tokens.where(revoked_at: nil).where("expires_in IS NULL OR created_at + expires_in * interval '1 second' > ?", Time.current).pluck(:scopes)
      @scopes = scope_sets.flat_map { |scopes| scopes.to_s.split }.uniq.sort
      @scope_status = SolidusMcp::ConnectionScopes.new(scope_sets)
      @policy = SolidusMcp::ConnectionPolicy.find_or_initialize_by(application: @application, user: @user)
      @policy.permissions = [] if @policy.new_record?
      @registry = SolidusMcp.registry
      @changes = @policy.persisted? ? @policy.policy_changes.order(id: :desc).limit(10) : []
    end
  end
end
