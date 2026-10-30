require "rails_helper"

RSpec.describe NotificationMailer do
  let(:owner) { create(:user, email_address: "owner@example.com") }
  let(:project) { create(:project, owner: owner) }
  let(:owner_email) { owner.email_address }
  let(:channel) { create(:notification_channel, :email, project: project, recipients: "a@example.com\n#{owner_email}") }
  let(:message) do
    Notifications::Message.new(title: "Raider: build failed — Shop", headline: "build failed",
                               summary: "1 failed", project_name: "Shop", branch: "main", commit: "abc Fix",
                               failures: [ "<script>alert(1)</script> (spec/a_spec.rb)" ], new_flaky: [],
                               pass_rate: 50, build_url: "http://example.com/b", pr_url: nil)
  end
  let(:mail) { described_class.build_notification(channel, message) }

  it "addresses recipients plus owner without duplicates" do
    expect(mail.to).to match_array([ "a@example.com", owner_email ])
  end

  it "includes the organization's owners and admins but not members or viewers" do
    org = project.organization
    create(:membership, organization: org, user: create(:user, email_address: "admin@example.com"), role: "admin")
    create(:membership, organization: org, user: create(:user, email_address: "member@example.com"), role: "member")
    create(:membership, organization: org, user: create(:user, email_address: "viewer@example.com"), role: "viewer")
    expect(mail.to).to match_array([ "a@example.com", owner_email, "admin@example.com" ])
  end

  it "omits the owner when include_owner is false" do
    channel.update!(include_owner: false, recipients: "a@example.com")
    expect(described_class.build_notification(channel, message).to).to eq([ "a@example.com" ])
  end

  it "formats subjects" do
    expect(mail.subject).to eq("[Raider Hideout] Shop: build failed on main")
    test = Notifications::Message.test(channel, url_options: { host: "example.com" })
    expect(described_class.build_notification(channel, test).subject).to eq("[Raider Hideout] #{project.name}: test notification")
  end

  it "escapes html and includes the build url in both parts" do
    expect(mail.html_part.body.to_s).to include("&lt;script&gt;").and include("http://example.com/b")
    expect(mail.html_part.body.to_s).not_to include("<script>")
    expect(mail.text_part.body.to_s).to include("http://example.com/b")
  end
end
