require "rails_helper"

RSpec.describe Invitation do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:inviter) { create(:user) }

  def issue(email = "guest@x.io", role: "member")
    described_class.issue!(organization: organization, email: email, role: role, invited_by: inviter)
  end

  it "only carries admin, member or viewer" do
    expect(described_class::ROLES).to eq(%w[admin member viewer])
    invitation = build(:invitation, role: "owner")
    expect(invitation.valid?).to be(false)
    expect(invitation.errors.full_messages).to eq([ "Invitations can be for admin, member or viewer" ])
  end

  it "normalizes and validates the email" do
    expect(build(:invitation, email: "  Guest@X.IO ").email).to eq("guest@x.io")
    expect(build(:invitation, email: "not an email").valid?).to be(false)
  end

  describe ".issue!" do
    it "stores only the SHA-256 digest of the raw token" do
      invitation, raw = issue
      expect(raw).to be_a(String).and(satisfy { |t| t.length >= 43 })
      expect(invitation.token_digest).to eq(Digest::SHA256.hexdigest(raw))
      stored = described_class.connection.select_rows("SELECT * FROM invitations").flatten.map(&:to_s)
      expect(stored).not_to include(raw)
      expect(invitation.expires_at).to be_within(5.seconds).of(7.days.from_now)
    end
  end

  describe ".find_by_token" do
    it "looks the invitation up by digest" do
      invitation, raw = issue
      expect(described_class.find_by_token(raw)).to eq(invitation)
      expect(described_class.find_by_token("nope")).to be_nil
      expect(described_class.find_by_token(nil)).to be_nil
      expect(described_class.find_by_token(invitation.token_digest)).to be_nil
    end
  end

  describe "#pending?" do
    it "is true for a fresh invitation" do
      expect(issue.first.pending?).to be(true)
      expect(described_class.pending).to include(organization.invitations.first)
    end

    it "is false once expired" do
      invitation, = issue
      travel 8.days do
        expect(invitation.pending?).to be(false)
        expect(described_class.pending).not_to include(invitation)
      end
    end

    it "is false once revoked" do
      invitation, = issue
      invitation.revoke!
      expect(invitation.reload.pending?).to be(false)
      expect(invitation.revoked_at).to be_present
      expect(described_class.pending).not_to include(invitation)
    end

    it "is false once accepted" do
      invitation, = issue
      invitation.update!(accepted_at: Time.current)
      expect(invitation.pending?).to be(false)
      expect(described_class.pending).not_to include(invitation)
    end
  end

  it "allows one pending invitation per organization and email" do
    first, = issue("guest@x.io")
    expect { issue("Guest@x.io") }
      .to raise_error(described_class::NotIssuable, "guest@x.io already has a pending invitation — resend it instead")
    first.revoke!
    expect { issue("guest@x.io") }.to change(described_class, :count).by(1)
    expect { described_class.issue!(organization: create(:organization), email: "guest@x.io", role: "viewer", invited_by: inviter) }
      .to change(described_class, :count).by(1)
  end

  it "stores the raw token encrypted and clears it on accept and revoke" do
    invitation, raw = issue("a@example.com")
    expect(invitation.token).to eq(raw)
    expect(invitation.ciphertext_for(:token)).not_to include(raw)
    invitation.revoke!
    expect(invitation.reload.token).to be_nil

    accepted, = issue("acc@example.com")
    accepted.accept!(create(:user, email_address: "acc@example.com"))
    expect(accepted.reload.token).to be_nil
  end

  it "replaces the token on reissue so the old link stops working" do
    invitation, old = issue("b@example.com")
    new_raw = invitation.reissue!
    expect(invitation.reload.token).to eq(new_raw)
    expect(described_class.find_by_token(old)).to be_nil
  end

  describe "#reissue!" do
    it "rotates the token and resets the expiry" do
      invitation, raw = issue
      travel 3.days do
        new_raw = invitation.reissue!
        expect(new_raw).not_to eq(raw)
        expect(invitation.reload.token_digest).to eq(Digest::SHA256.hexdigest(new_raw))
        expect(invitation.expires_at).to be_within(5.seconds).of(7.days.from_now)
        expect(described_class.find_by_token(raw)).to be_nil
        expect(described_class.find_by_token(new_raw)).to eq(invitation)
      end
    end
  end

  describe ".issue! guards" do
    it "refuses an existing member's email" do
      create(:membership, organization: organization, user: create(:user, email_address: "mia@x.io"))
      expect { issue(" MIA@x.io") }.to raise_error(described_class::NotIssuable, "mia@x.io is already a member")
    end

    it "revokes an expired, unrevoked invitation instead of being blocked by it" do
      stale, = issue
      travel 8.days do
        fresh, = issue
        expect(fresh).to be_persisted
        expect(stale.reload.revoked_at).to be_present
      end
    end

    it "maps a lost race on the unique index to NotIssuable" do
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      expect { issue }.to raise_error(described_class::NotIssuable, /already has a pending invitation/)
    end
  end

  describe "#accept!" do
    let(:guest) { create(:user, email_address: "guest@x.io") }

    it "creates the membership with the invite's role and marks it accepted" do
      invitation, = issue(role: "viewer")
      invitation.accept!(guest)
      expect(guest.role_in(organization)).to eq("viewer")
      expect(invitation.accepted_at).to be_present
    end

    it "refuses another email" do
      invitation, = issue
      expect { invitation.accept!(create(:user)) }.to raise_error(described_class::NotAcceptable, "Use the invited email address")
      expect(invitation.reload.accepted_at).to be_nil
    end

    it "can't be accepted twice, even from a stale copy" do
      invitation, = issue
      stale = described_class.find(invitation.id)
      invitation.accept!(guest)
      organization.memberships.find_by!(user: guest).destroy!
      expect { stale.accept!(guest) }.to raise_error(described_class::NotAcceptable)
      expect(guest.role_in(organization)).to be_nil
    end
  end
end
