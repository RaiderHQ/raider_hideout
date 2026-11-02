# One "re-run failed jobs" request made from Hideout: who asked, which attempt was the latest
# at the time, and what GitHub answered. `message` is GitHub's JSON message, redacted and
# truncated to 200 characters.
class BuildRerun < ApplicationRecord
  STATUSES = %w[pending accepted rejected failed].freeze
  MAX_MESSAGE = 200

  belongs_to :build
  belongs_to :user, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :attempt_before, presence: true
  validates :message, length: { maximum: MAX_MESSAGE }, allow_nil: true

  # The one time format for re-run copy: the guard line, the pending line and the record list.
  def clock = created_at.strftime("%H:%M")

  def starter_label = user&.email_address || "someone"

  def outcome_copy
    case status
    when "pending" then created_at > Build::RERUN_GUARD.ago ? "waiting for GitHub" : "no answer recorded"
    when "accepted" then "GitHub accepted"
    else Builds::Rerun.error_copy(http_status)
    end
  end
end
