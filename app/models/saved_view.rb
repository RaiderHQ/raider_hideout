class SavedView < ApplicationRecord
  LIMIT_PER_USER = 50

  belongs_to :project
  belongs_to :user

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: %i[project_id user_id], case_sensitive: false }
  validates :query, length: { maximum: Search::Filter::MAX_QUERY }
  validates :level, inclusion: { in: Search::Filter::LEVELS }
  validate :shared_name_unique, if: :shared?
  validate :within_limit, on: :create

  def self.visible_to(user, project)
    project.saved_views.where(user: user).or(project.saved_views.where(shared: true))
  end

  # Spec §5.3: owners edit their own views; admins and owners also edit shared views.
  def editable_by?(user, role)
    user_id == user.id || (shared? && Membership::RANK.fetch(role.to_s, -1) >= Membership::RANK.fetch("admin"))
  end

  private

  def shared_name_unique
    taken = SavedView.where(project_id: project_id, shared: true).where.not(id: id)
                     .where("LOWER(name) = ?", name.to_s.downcase).exists?
    errors.add(:name, "is already used by a shared view") if taken
  end

  def within_limit
    return if SavedView.where(project_id: project_id, user_id: user_id).count < LIMIT_PER_USER

    errors.add(:base, "You can have at most #{LIMIT_PER_USER} views in a project")
  end
end
