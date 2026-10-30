# Insert-only audit trail of quarantine changes (spec §5.2). actor is nil for "expired".
class QuarantineEvent < ApplicationRecord
  ACTIONS = %w[quarantined extended released expired].freeze
  MAX_NOTE = 500

  belongs_to :quarantine
  belongs_to :actor, class_name: "User", optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :expires_at, presence: true
  validates :note, length: { maximum: MAX_NOTE }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.for_project(project)
    joins(:quarantine).where(quarantines: { project_id: project.id })
  end

  def readonly?
    persisted? || super
  end
end
