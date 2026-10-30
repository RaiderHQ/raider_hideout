class ApiToken < ApplicationRecord
  PREFIX = "rdr_".freeze

  belongs_to :project
  validates :name, presence: true, length: { maximum: 100 }

  def self.digest(plain)
    OpenSSL::Digest::SHA256.hexdigest(plain)
  end

  def self.issue!(project:, name:)
    plain = PREFIX + SecureRandom.base58(32)
    [ create!(project: project, name: name, token_digest: digest(plain)), plain ]
  end

  # Personal (rdp_) tokens never match here, whatever their digest (spec §4.3).
  def self.authenticate(plain)
    return nil unless plain.is_a?(String) && plain.start_with?(PREFIX)

    find_by(token_digest: digest(plain))&.tap { |token| token.update_column(:last_used_at, Time.current) }
  end
end
