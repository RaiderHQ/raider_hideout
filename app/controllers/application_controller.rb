class ApplicationController < ActionController::Base
  include Authentication
  include FirstRun
  include RequireVerifiedEmail
  include Authorization
  include Pagy::Method
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_sentry_user

  rescue_from ActiveRecord::RecordNotFound do
    if request.format.html? || request.format.turbo_stream?
      render "application/not_found", status: :not_found, formats: [ :html ]
    else
      head :not_found
    end
  end

  private

  # Id only: no email or name reaches Sentry.
  def set_sentry_user
    Sentry.set_user(id: Current.user.id) if Sentry.initialized? && Current.user
  end

  def current_project
    @current_project ||= Current.user.projects.find_by!(slug: params[:project_id] || params[:id])
  end
  helper_method :current_project

  # Organization routes pass the slug as :id; routes nested under an organization
  # (e.g. memberships) pass it as :organization_id, so both keys must stay supported.
  def current_organization
    @current_organization ||= Current.user.organizations.find_by!(slug: params[:organization_id] || params[:id])
  end
end
