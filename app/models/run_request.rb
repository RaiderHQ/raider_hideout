# One "Run tests" request made from Hideout: who asked, the ref and tags, the repository and
# workflow from CI access at the time, and what GitHub answered. `message` is GitHub's JSON
# message, redacted and truncated to 200 characters. The build it produced is found by the
# GitHub run id (`builds.build_id`), so the repository's casing can't break the match.
class RunRequest < ApplicationRecord
  STATUSES = %w[pending accepted rejected failed].freeze
  LIVE = %w[pending accepted].freeze
  MAX_MESSAGE = 200
  REF_FORMAT = %r{\A(?!-)(?!.*\.\.)(?!.*//)(?!.*@\{)(?!.*\.lock\z)[A-Za-z0-9._/-]{1,200}(?<![/.])\z}
  TAGS_FORMAT = /\A[A-Za-z0-9@_:,.~! -]{1,200}\z/
  NO_ANSWER_AFTER = 10.minutes
  NO_RESULTS_AFTER = 2.hours
  PANEL_WINDOW = 24.hours
  PANEL_LIMIT = 5

  belongs_to :project
  belongs_to :user, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :ref, :repository, :workflow, presence: true
  validates :message, length: { maximum: MAX_MESSAGE }, allow_nil: true

  scope :live, -> { where(status: LIVE) }

  def self.recent(project)
    project.run_requests.includes(:user).where("created_at > ?", PANEL_WINDOW.ago)
           .order(created_at: :desc, id: :desc).limit(PANEL_LIMIT)
  end

  def build
    return nil if github_run_id.blank?
    return @build if defined?(@build)

    @build = project.builds.find_by(provider: "github_actions", build_id: github_run_id)
  end

  def clock = created_at.strftime("%H:%M")

  def requester_label = user&.email_address || "someone"

  def tags_label = tags.present? ? "Tags: #{tags}" : "All tests"

  # The panel state for this request.
  def state_copy
    case status
    when "pending" then created_at > NO_ANSWER_AFTER.ago ? "waiting for GitHub" : "no answer recorded"
    when "accepted" then accepted_copy
    when "rejected" then http_status ? Projects::RunTests.error_copy(http_status, message) : Projects::RunTests::COPY.fetch(401)
    else Projects::RunTests.error_copy(http_status, message)
    end
  end

  # The run on GitHub (html_url was validated when stored; re-checked here), else the workflow's runs page.
  def github_url
    base = "https://github.com/#{repository}/actions"
    if github_run_id.present?
      return html_url if html_url.to_s.start_with?("https://github.com/")

      return "#{base}/runs/#{github_run_id}"
    end

    "#{base}/workflows/#{workflow}"
  end

  private

  def accepted_copy
    return "started on GitHub" if github_run_id.blank?
    return "Build ##{build.id}" if build

    created_at > NO_RESULTS_AFTER.ago ? "waiting for results" : "no results yet"
  end
end
