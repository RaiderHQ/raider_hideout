# Account → Phone notifications: this user's devices, the event switches and one switch per
# visible project. Everything is scoped to Current.user.
class PhoneNotificationsController < ApplicationController
  def show
    @preference = Current.user.push_preference!
    @subscriptions = Current.user.push_subscriptions.order(:created_at, :id)
    @projects = Current.user.projects.order(:name)
    @muted_ids = Current.user.push_muted_projects.pluck(:project_id).to_set
    @public_key = VapidKey.current.public_key
  end

  def update
    visible_ids = Current.user.projects.pluck(:id)
    on_ids = Array(params[:project_ids]).filter_map { Integer(_1, 10, exception: false) } & visible_ids

    PushMutedProject.transaction do
      Current.user.push_preference!.update!(params.fetch(:push_preference, {}).permit(*PushPreference::SWITCHES))
      Current.user.push_muted_projects.delete_all
      (visible_ids - on_ids).each { Current.user.push_muted_projects.create!(project_id: _1) }
    end
    redirect_to phone_notifications_path, notice: "Phone notification settings saved."
  end
end
