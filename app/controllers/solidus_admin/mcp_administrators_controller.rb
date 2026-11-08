# frozen_string_literal: true

module SolidusAdmin
  class McpAdministratorsController < BaseController
    before_action :require_superadministrator

    rescue_from SolidusMcp::AccessDenied do
      head :forbidden
    end

    def index
      @superadmins = Spree.user_class.where(id: SolidusMcp::Administration.superadmin_user_ids)
      @page = [params[:page].to_i, 1].max
      entries = SolidusMcp::Administrator.order(:id).offset((@page - 1) * 25).limit(26).to_a
      @more = entries.size > 25
      @administrators = entries.first(25)
      @users = Spree.user_class.where(id: @administrators.map(&:user_id)).index_by(&:id)
      @changes = SolidusMcp::AdministratorChange.includes(:administrator).order(id: :desc).limit(20).to_a
      audit_ids = @changes.flat_map { |change| [change.actor_id, change.administrator.user_id] }
      @audit_users = Spree.user_class.where(id: audit_ids).index_by(&:id)
    end

    def search
      response.set_header("Cache-Control", "no-store")
      query = params.fetch(:query, "")
      unless query.is_a?(String) && query.length <= 100
        raise ActionController::BadRequest, "Invalid account search"
      end
      accounts = administrator_accounts
        .where("LOWER(email) LIKE ?", "#{Spree.user_class.sanitize_sql_like(query.strip.downcase)}%")
        .where.not(id: SolidusMcp::Administration.superadmin_user_ids)
        .where.not(id: SolidusMcp::Administrator.where(enabled: true).select(:user_id))
        .order(:email, :id).limit(21).to_a.select(&:admin?)
      more = accounts.length > 20
      accounts = accounts.first(20)
      assignments = SolidusMcp::Administrator.where(user_id: accounts.map(&:id)).index_by(&:user_id)
      render json: {items: accounts.map { |user|
        {id: user.id.to_s, email: user.email, lock_version: assignments[user.id]&.lock_version || -1}
      }, more: more}
    end

    def create
      submitted = params.require(:administrator).permit(:user_id, :lock_version)
      version = submitted.fetch(:lock_version, "-1").to_s
      raise ActionController::BadRequest, "Invalid assignment version" unless version.match?(/\A(?:-1|[0-9]+)\z/)
      user = Spree.user_class.find(submitted.fetch(:user_id))
      assignment = SolidusMcp::Administrator.find_or_initialize_by(user: user)
      assignment.change!(actor: current_solidus_admin_user, enabled: true, lock_version: version.to_i)
      redirect_to solidus_admin.mcp_administrators_path, notice: "MCP administrator assigned.", status: :see_other
    rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
      redirect_to solidus_admin.mcp_administrators_path, alert: "This user already has an assignment. Use its current controls below.", status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      redirect_to solidus_admin.mcp_administrators_path, alert: error.record.errors.full_messages.to_sentence, status: :see_other
    end

    def update
      submitted = params.require(:administrator).permit(:enabled, :lock_version)
      version = submitted[:lock_version]
      unless version.is_a?(String) && version.match?(/\A[0-9]+\z/) && %w[0 1].include?(submitted[:enabled])
        raise ActionController::BadRequest, "Invalid administrator assignment"
      end
      assignment = SolidusMcp::Administrator.find(params[:id])
      assignment.change!(actor: current_solidus_admin_user, enabled: submitted[:enabled] == "1", lock_version: version.to_i)
      redirect_to solidus_admin.mcp_administrators_path, notice: "MCP administrator assignment updated.", status: :see_other
    rescue ActiveRecord::StaleObjectError
      redirect_to solidus_admin.mcp_administrators_path, alert: "Another superadministrator changed this assignment. Reload before trying again.", status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      redirect_to solidus_admin.mcp_administrators_path, alert: error.record.errors.full_messages.to_sentence, status: :see_other
    end

    private

    def administrator_accounts
      users = Spree.user_class
      if users.reflect_on_association(:spree_roles)
        users.joins(:spree_roles).merge(Spree::Role.where(name: "admin")).distinct
      else
        # Custom user models may expose admin status as a boolean column.
        users.where(admin: true)
      end
    end

    def authorization_subject
      :mcp_administrators
    end

    def require_superadministrator
      head :forbidden unless SolidusMcp::Administration.superadmin?(current_solidus_admin_user)
    end
  end
end
