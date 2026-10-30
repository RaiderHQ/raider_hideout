class Membership < ApplicationRecord
  ROLES = %w[owner admin member viewer].freeze
  RANK = { "viewer" => 0, "member" => 1, "admin" => 2, "owner" => 3 }.freeze

  belongs_to :organization
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }

  after_destroy_commit :disconnect_streams
  after_destroy :delete_personal_saved_views

  def at_least?(min_role)
    RANK.fetch(role, -1) >= RANK.fetch(min_role.to_s)
  end

  # Cable checks membership only on subscribe; dropping the connection makes the
  # client resubscribe, and ProjectStreamsChannel then rejects this organization's
  # projects. The user's other tabs reconnect at once (ruling R3).
  def disconnect_streams
    return unless user
    ActionCable.server.remote_connections.where(current_user: user).disconnect(reconnect: true)
  end

  # Spec §5.3: leaving an organization deletes your personal views in its projects;
  # shared ones stay for the team.
  def delete_personal_saved_views
    SavedView.where(user_id: user_id, shared: false, project_id: organization.projects.select(:id)).delete_all
  end
end
