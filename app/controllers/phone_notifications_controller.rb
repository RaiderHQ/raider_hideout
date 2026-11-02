# Account → Phone notifications: this user's devices, the event switches and one switch per
# visible project. Everything is scoped to Current.user.
class PhoneNotificationsController < ApplicationController
  def show
    @preference = Current.user.push_preference!
    @subscriptions = Current.user.push_subscriptions.order(:created_at, :id)
    @projects = Current.user.projects.order(:name)
    @muted_ids = Current.user.push_muted_projects.pluck(:project_id).to_set
    @public_key = VapidKey.current.public_key
  rescue VapidKey::Misconfigured => e
    @vapid_error = e.message
  end

  def update
    visible_ids = Current.user.projects.pluck(:id)
    # Only projects the page listed (and the user can still see) are touched; a project that
    # appeared after the page was rendered keeps its current state.
    shown_ids = integer_ids(:shown_project_ids) & visible_ids
    on_ids = integer_ids(:project_ids) & shown_ids

    PushMutedProject.transaction do
      Current.user.push_preference!.update!(switch_params)
      Current.user.push_muted_projects.where(project_id: shown_ids).delete_all
      (shown_ids - on_ids).each { Current.user.push_muted_projects.create!(project_id: _1) }
    end
    redirect_to phone_notifications_path, notice: "Phone notification settings saved."
  end

  private

  def integer_ids(name)
    Array(params[name]).filter_map { Integer(_1, 10, exception: false) if _1.is_a?(String) }
  end

  # A non-hash push_preference (e.g. a plain string) is ignored rather than raising.
  def switch_params
    raw = params[:push_preference]
    raw.respond_to?(:permit) ? raw.permit(*PushPreference::SWITCHES) : {}
  end
end
