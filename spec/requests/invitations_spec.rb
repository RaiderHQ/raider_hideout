require "rails_helper"

RSpec.describe "Invitations", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:org) { create(:organization, name: "Acme") }
  let(:user) { create(:user) }

  def join(role, as: create(:user))
    create(:membership, organization: org, user: as, role: role)
  end

  def invite(email = "guest@x.io", role: "member", **extra)
    post organization_invitations_path(org), params: { invitation: { email: email, role: role, **extra } }
  end

  def issue(email = "guest@x.io")
    Invitation.issue!(organization: org, email: email, role: "member", invited_by: user)
  end

  describe "create" do
    before do
      join("admin", as: user)
      sign_in(user)
    end

    it "keeps the raw token out of the mail job arguments" do
      expect { invite("x@example.com") }
        .to have_enqueued_mail(InvitationMailer, :invite).with(an_instance_of(Invitation))
      invitation = org.invitations.find_by!(email: "x@example.com")
      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.inspect
      expect(jobs).not_to include(invitation.token)
    end

    it "creates the invitation and sends one email" do
      expect { invite(" Guest@X.io ", role: "viewer") }.to have_enqueued_mail(InvitationMailer, :invite).exactly(:once)
      invitation = org.invitations.sole
      expect(invitation).to have_attributes(email: "guest@x.io", role: "viewer", invited_by: user)
      expect(response).to redirect_to(organization_memberships_path(org))
      expect(flash[:notice]).to eq("Invitation sent to guest@x.io.")
    end

    it "refuses an existing member's email" do
      member = join("member", as: create(:user, email_address: "mia@x.io"))
      expect { invite("MIA@x.io") }.not_to change(Invitation, :count)
      expect(flash[:alert]).to eq("#{member.user.email_address} is already a member")
      expect(enqueued_jobs).to be_empty
    end

    it "refuses an email with a pending invitation" do
      issue
      expect { invite("guest@x.io") }.not_to change(Invitation, :count)
      expect(flash[:alert]).to eq("guest@x.io already has a pending invitation — resend it instead")
    end

    it "lets a new invite replace an expired, unrevoked one" do
      stale, = issue
      travel 8.days do
        expect { invite("guest@x.io") }.to change(Invitation, :count).by(1)
        expect(flash[:notice]).to eq("Invitation sent to guest@x.io.")
        expect(stale.reload.revoked_at).to be_present
      end
    end

    it "rejects a role of owner" do
      expect { invite(role: "owner") }.not_to change(Invitation, :count)
      expect(flash[:alert]).to eq("Invitations can be for admin, member or viewer")
    end

    it "ignores token_digest and organization_id params (Review Focus 5)" do
      other = create(:organization)
      invite(token_digest: "forged", organization_id: other.id, invited_by_id: create(:user).id)
      invitation = Invitation.sole
      expect(invitation.organization).to eq(org)
      expect(invitation.invited_by).to eq(user)
      expect(invitation.token_digest).not_to eq("forged")
      expect(invitation.token_digest).to match(/\A\h{64}\z/)
    end
  end

  describe "resend" do
    before do
      join("owner", as: user)
      sign_in(user)
    end

    it "issues a new token, invalidates the old link and sends an email" do
      invitation, old_token = issue
      old_digest = invitation.token_digest
      travel 2.days do
        expect { post resend_organization_invitation_path(org, invitation) }
          .to have_enqueued_mail(InvitationMailer, :invite).exactly(:once)
        expect(invitation.reload.token_digest).not_to eq(old_digest)
        expect(invitation.expires_at).to be_within(5.seconds).of(7.days.from_now)
        expect(Invitation.find_by_token(old_token)).to be_nil
        get invitation_acceptance_path(token: old_token)
        expect(response).to have_http_status(:not_found)
      end
    end

    it "404s for a revoked invitation" do
      invitation, = issue
      invitation.revoke!
      post resend_organization_invitation_path(org, invitation)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "destroy (revoke)" do
    it "revokes the invitation" do
      join("admin", as: user)
      sign_in(user)
      invitation, raw = issue
      delete organization_invitation_path(org, invitation)
      expect(response).to redirect_to(organization_memberships_path(org))
      expect(invitation.reload.revoked_at).to be_present
      get invitation_acceptance_path(token: raw)
      expect(response).to have_http_status(:not_found)
    end

    it "404s for another organization's invitation" do
      join("admin", as: user)
      sign_in(user)
      foreign = create(:invitation)
      delete organization_invitation_path(org, foreign)
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.revoked_at).to be_nil
    end
  end

  describe "authorization" do
    %w[member viewer].each do |role|
      it "403s a #{role} on create, resend and revoke" do
        join(role, as: user)
        invitation = create(:invitation, organization: org)
        sign_in(user)
        expect { invite }.not_to change(Invitation, :count)
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include("You need the admin role or higher to do this.")
        post resend_organization_invitation_path(org, invitation)
        expect(response).to have_http_status(:forbidden)
        delete organization_invitation_path(org, invitation)
        expect(response).to have_http_status(:forbidden)
        expect(invitation.reload.revoked_at).to be_nil
      end
    end

    it "404s for non-members" do
      invitation = create(:invitation, organization: org)
      sign_in(user)
      invite
      expect(response).to have_http_status(:not_found)
      post resend_organization_invitation_path(org, invitation)
      expect(response).to have_http_status(:not_found)
      delete organization_invitation_path(org, invitation)
      expect(response).to have_http_status(:not_found)
      expect(Invitation.count).to eq(1)
    end
  end

  describe "members page" do
    it "shows admins the invite form and pending invitations" do
      join("admin", as: user)
      create(:invitation, organization: org, email: "pending@x.io")
      create(:invitation, organization: org, email: "gone@x.io", revoked_at: Time.current)
      sign_in(user)
      get organization_memberships_path(org)
      expect(response.body).to include("Send invitation", "pending@x.io", "Resend", "Revoke")
      expect(response.body).not_to include("gone@x.io")
    end

    it "hides invitations from members" do
      join("member", as: user)
      create(:invitation, organization: org, email: "pending@x.io")
      sign_in(user)
      get organization_memberships_path(org)
      expect(response.body).not_to include("Send invitation", "pending@x.io")
    end
  end

  describe "without SMTP" do
    include LogCapture

    before do
      join("admin", as: user)
      sign_in(user)
      mail_disabled!
    end

    def link_token = Rack::Utils.parse_query(URI(CGI.unescapeHTML(response.body[%r{http://www\.example\.com/invitations/accept\?token=[^"<\s]+}])).query)["token"]

    it "shows the invite link once instead of mailing it" do
      expect { invite("x@example.com") }.not_to have_enqueued_mail(InvitationMailer, :invite)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("This server sends no email")
      expect(Invitation.find_by_token(link_token).email).to eq("x@example.com")
    end

    it "rotates the link on Show new link, so the old one stops working" do
      invitation, old_token = issue("x@example.com")
      expect { post resend_organization_invitation_path(org, invitation) }.not_to have_enqueued_mail(InvitationMailer, :invite)
      expect(response).to have_http_status(:ok)
      expect(Invitation.find_by_token(link_token)).to eq(invitation)
      expect(Invitation.find_by_token(old_token)).to be_nil
    end

    it "labels the button Show new link" do
      issue("x@example.com")
      get organization_memberships_path(org)
      expect(response.body).to include("Show new link")
      expect(response.body).not_to include(">Resend<")
    end

    it "keeps the link out of the log" do
      log = capture_log { invite("x@example.com") }
      expect(log).not_to include(link_token)
    end
  end
end
