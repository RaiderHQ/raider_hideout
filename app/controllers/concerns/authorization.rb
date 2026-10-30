module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_role, :role_at_least?
  end

  private

  def current_role
    @current_role ||= Current.user.role_in(authorization_organization)
  end

  # The organization whose role gates the request. Project pages resolve it
  # through the project; organization controllers override it with
  # current_organization so a project slug can never shadow an organization slug.
  def authorization_organization
    current_project.organization
  end

  def role_at_least?(min, organization = nil)
    role = organization ? Current.user.role_in(organization) : current_role
    role.present? && Membership::RANK.fetch(role) >= Membership::RANK.fetch(min.to_s)
  end

  def require_role!(min, organization = nil)
    return if role_at_least?(min, organization)

    @required_role = min.to_s
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden }
      format.any { head :forbidden }
    end
  end
end
