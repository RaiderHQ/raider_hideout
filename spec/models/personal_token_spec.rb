require "rails_helper"

RSpec.describe PersonalToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  after { travel_back }

  def issue(name = "Laptop", days = 90, owner: user)
    described_class.issue!(user: owner, name: name, expires_in_days: days)
  end

  it "issues rdp_ plus 32 base58 characters and stores only the digest and the 8-character prefix" do
    token, plain = issue

    expect(plain).to match(/\Ardp_[1-9A-HJ-NP-Za-km-z]{32}\z/)
    expect(token).to be_persisted
    expect(token.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(plain))
    expect(token.token_prefix).to eq(plain.first(8))
    expect(token.attributes.values).not_to include(plain)
  end

  it "sets the expiry from 30, 90 or 365 days, or never" do
    freeze_time do
      expect(issue("a", 30).first.expires_at).to eq(30.days.from_now)
      expect(issue("b", 90).first.expires_at).to eq(90.days.from_now)
      expect(issue("c", 365).first.expires_at).to eq(365.days.from_now)
      expect(issue("d", nil).first.expires_at).to be_nil
    end
    expect(described_class::DEFAULT_EXPIRY_DAYS).to eq(90)
  end

  it "rejects any other expiry" do
    [ 7, 0, 366, "90", "30", "never", "", 30.0, 90.0, Rational(90), BigDecimal("365") ].each do |days|
      expect { issue("x#{days}", days) }
        .to raise_error(ActiveRecord::RecordInvalid, /Expiry must be 30, 90 or 365 days, or never/)
    end
  end

  it "is active until it expires or is revoked, and revoking keeps the row" do
    token, = issue("short", 30)
    expect(token.status).to eq("active")
    expect(described_class.active).to include(token)

    travel 30.days + 1.second
    expect(token.status).to eq("expired")
    expect(described_class.active).not_to include(token)

    forever, = issue("forever", nil)
    forever.revoke!
    expect(forever.reload.revoked_at).to be_present
    expect(forever.status).to eq("revoked")
    expect(described_class.active).not_to include(forever)
    expect(described_class.exists?(forever.id)).to be(true)
  end

  it "allows at most 20 active tokens; revoked and expired ones do not count" do
    20.times { |i| issue("token #{i}") }
    expect { issue("token 20") }
      .to raise_error(ActiveRecord::RecordInvalid, /You already have 20 active tokens; revoke one first/)

    user.personal_tokens.first.revoke!
    expect { issue("token 20") }.not_to raise_error
  end

  it "requires a 1–100 character name, unique among the user's active tokens" do
    expect { issue("  ") }.to raise_error(ActiveRecord::RecordInvalid, /Name can't be blank/)
    expect { issue("a" * 101) }.to raise_error(ActiveRecord::RecordInvalid, /Name is too long/)
    expect(issue("  Padded  ").first.name).to eq("Padded")

    issue("Laptop")
    expect { issue("Laptop") }
      .to raise_error(ActiveRecord::RecordInvalid, /Name is already used by one of your active tokens/)
    expect { issue("Laptop", owner: create(:user)) }.not_to raise_error

    user.personal_tokens.find_by!(name: "Laptop").revoke!
    expect { issue("Laptop") }.not_to raise_error
  end

  describe ".authenticate" do
    it "returns the active token and writes last_used_at at most once a minute" do
      token, plain = issue
      start = Time.zone.parse("2026-10-25 12:00:00")

      travel_to(start) { expect(described_class.authenticate(plain)).to eq(token) }
      expect(token.reload.last_used_at).to eq(start)

      travel_to(start + 59.seconds) { described_class.authenticate(plain) }
      expect(token.reload.last_used_at).to eq(start)

      travel_to(start + 61.seconds) { described_class.authenticate(plain) }
      expect(token.reload.last_used_at).to eq(start + 61.seconds)
    end

    it "rejects blank, unknown, expired and revoked tokens" do
      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("")).to be_nil
      expect(described_class.authenticate("rdp_#{'x' * 32}")).to be_nil

      revoked, revoked_plain = issue("revoked")
      revoked.revoke!
      expect(described_class.authenticate(revoked_plain)).to be_nil

      _, expiring_plain = issue("expiring", 30)
      travel 31.days
      expect(described_class.authenticate(expiring_plain)).to be_nil
    end

    it "rejects project (rdr_) tokens, even one whose digest is stored here" do
      project_plain = ApiToken.issue!(project: create(:project, owner: user), name: "CI").last
      expect(described_class.authenticate(project_plain)).to be_nil

      described_class.create!(user: user, name: "forged", token_digest: described_class.digest(project_plain),
                              token_prefix: project_plain.first(8))
      expect(described_class.authenticate(project_plain)).to be_nil
    end
  end

  it "is deleted with its user by the database" do
    owner = create(:user, with_personal_organization: false)
    issue("doomed", owner: owner)

    User.where(id: owner.id).delete_all

    expect(described_class.count).to eq(0)
  end

  it "filters Authorization and token values from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter("authorization" => "Bearer rdp_x", "token" => "rdp_y"))
      .to eq("authorization" => "[FILTERED]", "token" => "[FILTERED]")
  end
end
