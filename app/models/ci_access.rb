# A project's CI credential (slice 2): one GitHub token, encrypted, used to re-run failed
# jobs. The token is never rendered, logged or inspected; `redact` masks it in any text
# that came back from GitHub.
class CiAccess < ApplicationRecord
  TOKEN_FORMAT = /\A(github_pat_[A-Za-z0-9_]{20,255}|ghp_[A-Za-z0-9]{36})\z/
  INVALID_TOKEN = "That doesn't look like a GitHub token.".freeze

  # Hash whose string forms hide the token.
  class RedactedAttributes < Hash
    def inspect = to_h.merge("token" => "[REDACTED]").inspect
    alias_method :to_s, :inspect
  end

  belongs_to :project

  encrypts :token

  validates :project_id, uniqueness: true
  validate :token_has_valid_format

  def attributes = RedactedAttributes[super]

  def inspect
    "#<CiAccess id=#{id.inspect} project_id=#{project_id.inspect} provider=#{provider.inspect} token=[REDACTED]>"
  end

  def redact(text)
    return text.to_s if token.blank?

    text.to_s.gsub(token) { "[token]" }
  end

  private

  def token_has_valid_format
    errors.add(:base, INVALID_TOKEN) unless token.is_a?(String) && TOKEN_FORMAT.match?(token)
  end
end
