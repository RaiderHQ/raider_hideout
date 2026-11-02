# A project's CI credential (slice 2): one GitHub token, encrypted, used to re-run failed
# jobs. The token is never rendered, logged or inspected; `redact` masks it in any text
# that came back from GitHub.
class CiAccess < ApplicationRecord
  TOKEN_FORMAT = /\A(github_pat_[A-Za-z0-9_]{20,255}|ghp_[A-Za-z0-9]{36})\z/
  INVALID_TOKEN = "That doesn't look like a GitHub token.".freeze

  belongs_to :project

  encrypts :token

  validates :project_id, uniqueness: true
  validate :token_has_valid_format

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

  private

  def token_has_valid_format
    errors.add(:base, INVALID_TOKEN) unless token.is_a?(String) && TOKEN_FORMAT.match?(token)
  end
end
