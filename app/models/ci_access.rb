# A project's CI credential (slice 2): one GitHub token, encrypted, used to re-run failed
# jobs and to start the test workflow. The token is never rendered, logged or inspected;
# `redact` masks it in any text that came back from GitHub.
#
# Run tests settings (raider app plan A): the repository (owner/name), the workflow file and
# an optional workflow_dispatch input that takes tags. Each is a path segment or an input
# name, so the formats are strict and the client re-checks them before every request.
class CiAccess < ApplicationRecord
  TOKEN_FORMAT = /\A(github_pat_[A-Za-z0-9_]{20,255}|ghp_[A-Za-z0-9]{36})\z/
  INVALID_TOKEN = "That doesn't look like a GitHub token.".freeze

  WORKFLOW_FORMAT = /\A[A-Za-z0-9_.-]{1,100}\.ya?ml\z/
  TAG_INPUT_FORMAT = /\A[A-Za-z_][A-Za-z0-9_-]{0,99}\z/
  REPOSITORY_ERROR = "Enter the repository as owner/name.".freeze
  WORKFLOW_ERROR = "Enter a workflow file name ending in .yml or .yaml.".freeze
  TAG_INPUT_ERROR = "Use letters, numbers, - and _ for the input name.".freeze
  DETECT_LIMIT = 50

  belongs_to :project

  encrypts :token

  normalizes :repository, :workflow, :tag_input, with: ->(value) { value.strip.presence }

  validates :project_id, uniqueness: true
  validate :token_has_valid_format
  validate :repository_has_valid_format, if: -> { repository.present? }
  validates :workflow, format: { with: WORKFLOW_FORMAT, message: WORKFLOW_ERROR }, allow_nil: true
  validates :tag_input, format: { with: TAG_INPUT_FORMAT, message: TAG_INPUT_ERROR }, allow_nil: true

  # Never carries the token into as_json / to_json.
  def serializable_hash(options = nil)
    super.except("token")
  end

  TOKEN_SHAPE = /github_pat_[A-Za-z0-9_]{8,}|gh[pousr]_[A-Za-z0-9]{8,}/

  # Masks the exact token, then anything token-shaped (GitHub may echo a prefix).
  def self.mask(text, token = nil)
    out = text.to_s
    out = out.gsub(token) { "[token]" } if token.present?
    out.gsub(TOKEN_SHAPE) { "[token]" }
  end

  def redact(text) = self.class.mask(text, token)

  # [owner, repo] from the saved repository, or nil when it is blank or malformed.
  def repository_parts = self.class.split_repository(repository)

  # "owner/repo" from the latest GitHub Actions build whose ci_run_key parses, or nil.
  def detected_repository
    project.builds.where(provider: "github_actions").where.not(ci_run_key: nil)
           .order(id: :desc).limit(DETECT_LIMIT).each do |build|
      owner, repo, = Github::Repository.from_build(build)
      return "#{owner}/#{repo}" if owner
    end
    nil
  end

  def run_tests_ready?
    TOKEN_FORMAT.match?(token.to_s) && repository_parts.present? && WORKFLOW_FORMAT.match?(workflow.to_s)
  end

  def self.split_repository(value)
    return nil unless value.is_a?(String)

    parts = value.split("/", -1)
    parts if parts.size == 2 && parts.all? { |part| Github::Repository.valid_part?(part) }
  end

  private

  def repository_has_valid_format
    errors.add(:repository, REPOSITORY_ERROR) unless repository_parts
  end

  def token_has_valid_format
    errors.add(:base, INVALID_TOKEN) unless token.is_a?(String) && TOKEN_FORMAT.match?(token)
  end
end
