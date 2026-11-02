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
end
