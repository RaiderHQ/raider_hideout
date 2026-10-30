require "rails_helper"

RSpec.describe NotificationChannel do
  let(:slack_url) { "https://hooks.slack.com/services/T0/B0/xyz" }

  it "accepts valid Slack and Teams webhooks" do
    expect(build(:notification_channel, webhook_url: slack_url)).to be_valid
    [ "https://prod-12.westeurope.logic.azure.com/workflows/abc/triggers/manual/paths/invoke?sig=s",
      "https://default123.environment.api.powerplatform.com/powerautomate/automations/direct/workflows/x/triggers/manual/paths/invoke?sig=s" ].each do |url|
      expect(build(:notification_channel, :teams, webhook_url: url)).to be_valid
    end
  end

  it "normalizes email recipients" do
    channel = build(:notification_channel, :email, recipients: "a@x.io, B@X.io\nb@x.io")
    expect(channel).to be_valid
    expect(channel.recipient_list).to eq(%w[a@x.io b@x.io])
    expect(channel.recipients).to eq("a@x.io\nb@x.io")
  end

  describe "invalid channels" do
    it "rejects bad Slack hosts and schemes" do
      [ "http://hooks.slack.com/services/x", "https://evil.com/hooks.slack.com", "", nil ].each do |url|
        channel = build(:notification_channel, webhook_url: url)
        expect(channel).not_to be_valid
        expect(channel.errors[:webhook_url]).to be_present
      end
      expect(build(:notification_channel, webhook_url: "https://evil.com/x").tap(&:valid?).errors[:webhook_url])
        .to include("must be a Slack incoming webhook URL")
    end

    it "rejects bad Teams hosts" do
      [ "https://logic.azure.com.evil.com/x", "", nil ].each do |url|
        channel = build(:notification_channel, :teams, webhook_url: url)
        expect(channel).not_to be_valid
      end
      expect(build(:notification_channel, :teams, webhook_url: "https://evil.com").tap(&:valid?).errors[:webhook_url])
        .to include("must be a Teams Workflows webhook URL")
    end

    it "rejects too many or malformed recipients" do
      many = (1..21).map { |i| "u#{i}@x.io" }.join(",")
      expect(build(:notification_channel, :email, recipients: many)).not_to be_valid
      expect(build(:notification_channel, :email, recipients: "not-an-email")).not_to be_valid
    end

    it "requires a pattern for the pattern filter" do
      expect(build(:notification_channel, branch_filter: "pattern", branch_pattern: "")).not_to be_valid
      expect(build(:notification_channel, branch_filter: "pattern", branch_pattern: "release/*")).to be_valid
    end

    it "bounds pass_rate_below to 1..100" do
      expect(build(:notification_channel, pass_rate_below: 0)).not_to be_valid
      expect(build(:notification_channel, pass_rate_below: 101)).not_to be_valid
      expect(build(:notification_channel, pass_rate_below: 90)).to be_valid
    end

    it "rejects unknown kinds and branch filters" do
      expect(build(:notification_channel, kind: "sms")).not_to be_valid
      expect(build(:notification_channel, branch_filter: "nope")).not_to be_valid
    end
  end

  it "strips the stored webhook URL" do
    channel = create(:notification_channel, webhook_url: " https://hooks.slack.com/services/T/B/x\n")
    expect(channel.reload.webhook_url).to eq("https://hooks.slack.com/services/T/B/x")
    expect(channel.masked_target).to eq("hooks.slack.com/…//B/x")
  end

  it "compares hosts case-insensitively" do
    expect(build(:notification_channel, webhook_url: "https://HOOKS.SLACK.COM/services/T/B/x")).to be_valid
  end

  it "rejects host bypasses and accepts powerautomate" do
    expect(build(:notification_channel, webhook_url: "https://hooks.slack.com@evil.com/x")).not_to be_valid
    expect(build(:notification_channel, webhook_url: "https://hooks.slack.com./x")).not_to be_valid
    expect(build(:notification_channel, :teams, webhook_url: "https://x.powerautomate.com/a?sig=s")).to be_valid
  end

  it "caps the invalid recipients message" do
    channel = build(:notification_channel, :email, recipients: "a,b,c,d,e")
    channel.valid?
    expect(channel.errors[:recipients].join).to include("a, b, c and 2 more")
  end

  it "adds no webhook error for an unknown kind" do
    channel = build(:notification_channel, kind: "sms")
    channel.valid?
    expect(channel.errors[:webhook_url]).to be_empty
  end

  it "accepts configured extra hosts in test" do
    expect(build(:notification_channel, :teams, webhook_url: "http://127.0.0.1:9999/teams")).to be_valid
  end

  describe "#masked_target" do
    it "masks webhook URLs" do
      channel = build(:notification_channel, webhook_url: "https://hooks.slack.com/services/T0/B0/abcdWXYZ")
      expect(channel.masked_target).to eq("hooks.slack.com/…/WXYZ")
    end

    it "counts email recipients" do
      expect(build(:notification_channel, :email, recipients: "a@x.io,b@x.io", include_owner: false).masked_target).to eq("2 recipients")
      expect(build(:notification_channel, :email, recipients: "a@x.io", include_owner: true).masked_target).to eq("1 recipient + owners & admins")
    end
  end

  it "redacts the webhook URL from text" do
    channel = build(:notification_channel, webhook_url: "https://hooks.slack.com/services/T0/B0/abcdWXYZ")
    out = channel.redact("POST https://hooks.slack.com/services/T0/B0/abcdWXYZ failed")
    expect(out).not_to include("abcdWXYZ")
    expect(out).to include("WXYZ")
  end

  it "redacts the JSON-escaped and query-less forms" do
    channel = build(:notification_channel, :teams)
    url = channel.webhook_url
    base = url.split("?").first
    out = channel.redact("a #{url.gsub('/', '\\/')} b #{base} c #{url}")
    expect(out).not_to include("workflows")
    expect(out).not_to include("sig=s")
  end

  it "redacts HTML-escaped and combined encoded forms of the full URL" do
    channel = build(:notification_channel, :teams, webhook_url: "https://prod-1.logic.azure.com/workflows/abc?api=1&sig=SECRET")
    url = channel.webhook_url
    forms = [ url, url.gsub("&", "&amp;"), url.gsub("/", "\\/"), url.gsub("&", "&amp;").gsub("/", "\\/") ]
    out = channel.redact(forms.join(" | "))
    expect(out).not_to include("SECRET")
    expect(out).not_to include("workflows")
  end

  it "encrypts the webhook URL at rest" do
    channel = create(:notification_channel, webhook_url: slack_url)
    raw = described_class.connection.select_value("SELECT webhook_url FROM notification_channels WHERE id = #{channel.id}")
    expect(raw).not_to eq(slack_url)
    expect(raw).not_to include("xyz")
    expect(channel.reload.webhook_url).to eq(slack_url)
  end

  it "is destroyed with its project" do
    channel = create(:notification_channel)
    expect { channel.project.destroy }.to change(described_class, :count).by(-1)
  end
end
