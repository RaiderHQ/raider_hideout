# A test whose failures are reported as quarantined until expires_at (spec §5.2).
# Activity is computed from expires_at, never from the nightly job.
class Quarantine < ApplicationRecord
  DURATIONS = [ 7, 14, 30 ].freeze
  DEFAULT_DURATION = 14
  MAX_REASON = 500

  class Inactive < StandardError; end

  class AlreadyQuarantined < StandardError
    attr_reader :quarantine

    def initialize(quarantine)
      @quarantine = quarantine
      super("already quarantined until #{quarantine.expires_at.iso8601}")
    end
  end

  belongs_to :project
  belongs_to :test_case
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :released_by, class_name: "User", optional: true
  has_many :events, class_name: "QuarantineEvent", dependent: :delete_all, inverse_of: :quarantine

  normalizes :reason, with: ->(reason) { reason.strip }

  validates :reason, presence: true, length: { maximum: MAX_REASON }
  validates :expires_at, presence: true
  validate :one_active_per_test_case, on: :create

  scope :active, ->(now = Time.current) { where(released_at: nil).where(arel_table[:expires_at].gt(now)) }

  # The test case row is locked so two members cannot both quarantine it.
  def self.quarantine!(test_case:, user:, reason:, days:, now: Time.current)
    transaction do
      test_case.lock!
      existing = active(now).find_by(test_case_id: test_case.id)
      raise AlreadyQuarantined, existing if existing

      quarantine = new(project_id: test_case.project_id, test_case: test_case, created_by: user, reason: reason)
      quarantine.expires_at = now + duration!(quarantine, days).days
      quarantine.save!
      quarantine.events.create!(action: "quarantined", actor: user, expires_at: quarantine.expires_at)
      quarantine
    end
  end

  def self.duration!(record, days)
    value = Integer(days.to_s, 10, exception: false)
    return value if DURATIONS.include?(value)

    record.errors.add(:base, "Duration must be 7, 14 or 30 days")
    raise ActiveRecord::RecordInvalid, record
  end

  def active?(now = Time.current)
    released_at.nil? && expires_at > now
  end

  def extend_by!(user:, days:, note: nil, now: Time.current)
    with_lock do
      raise Inactive unless active?(now)

      self.expires_at = now + self.class.duration!(self, days).days
      save!
      events.create!(action: "extended", actor: user, expires_at: expires_at, note: note.presence)
    end
    self
  end

  def release!(user:, note: nil, now: Time.current)
    with_lock do
      raise Inactive unless active?(now)

      update!(released_at: now, released_by: user)
      events.create!(action: "released", actor: user, expires_at: expires_at, note: note.presence)
    end
    self
  end

  private

  def one_active_per_test_case
    return unless test_case_id && Quarantine.active.where(test_case_id: test_case_id).exists?

    errors.add(:test_case, "is already quarantined")
  end
end
