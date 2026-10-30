require "rails_helper"

RSpec.describe "Notification channels", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:slack_url) { "https://hooks.slack.com/services/T0/B0/abcdWXYZ" }

  before { sign_in(user) }

  def create_params(overrides = {})
    { notification_channel: { kind: "slack", name: "#qa", webhook_url: slack_url }.merge(overrides) }
  end

  describe "CRUD" do
    it "creates, lists, edits and deletes a Slack channel" do
      post project_notification_channels_path(project), params: create_params
      expect(response).to redirect_to(project_notification_channels_path(project))
      channel = project.notification_channels.last
      expect(channel).to have_attributes(kind: "slack", name: "#qa", webhook_url: slack_url)

      get project_notification_channels_path(project)
      expect(response.body).to include("#qa", "hooks.slack.com/…/WXYZ")

      patch project_notification_channel_path(project, channel), params: { notification_channel: { name: "#renamed" } }
      expect(channel.reload.name).to eq("#renamed")

      delete project_notification_channel_path(project, channel)
      expect(project.notification_channels.count).to eq(0)
    end

    it "creates Teams and email channels" do
      post project_notification_channels_path(project), params: {
        notification_channel: { kind: "teams", name: "Teams", webhook_url: "https://x.logic.azure.com/workflows/a?sig=b" }
      }
      post project_notification_channels_path(project), params: {
        notification_channel: { kind: "email", name: "Mail", recipients: "A@example.com", include_owner: "0" }
      }
      expect(project.notification_channels.pluck(:kind)).to contain_exactly("teams", "email")
      expect(project.notification_channels.find_by(kind: "email").recipient_list).to eq([ "a@example.com" ])
    end

    it "drops a webhook_url submitted when creating an email channel" do
      post project_notification_channels_path(project), params: {
        notification_channel: { kind: "email", name: "Mail", recipients: "a@example.com", webhook_url: slack_url }
      }
      expect(project.notification_channels.last.webhook_url).to be_nil
    end

    it "renders the new form for each kind" do
      NotificationChannel::KINDS.each do |kind|
        get new_project_notification_channel_path(project, kind: kind)
        expect(response).to have_http_status(:ok)
      end
    end

    it "labels the include_owner checkbox for the organization's owners and admins" do
      get new_project_notification_channel_path(project, kind: "email")
      expect(response.body).to include("Also send to the organization's owners and admins")
    end

    it "re-renders with an error for an invalid URL" do
      post project_notification_channels_path(project), params: create_params(webhook_url: "https://evil.example.com/x")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be a Slack incoming webhook URL")
      expect(project.notification_channels.count).to eq(0)
    end

    it "shows the empty state" do
      get project_notification_channels_path(project)
      expect(response.body).to include("Slack", "Microsoft Teams", "email")
    end
  end

  describe "webhook secrecy" do
    let!(:channel) { create(:notification_channel, project: project, webhook_url: slack_url) }

    it "never renders the full URL on index or edit" do
      [ project_notification_channels_path(project), edit_project_notification_channel_path(project, channel) ].each do |path|
        get path
        expect(response.body).to include("hooks.slack.com/…/WXYZ")
        expect(response.body).not_to include("abcdWXYZ")
      end
    end

    it "keeps the stored URL when edited with a blank one" do
      patch project_notification_channel_path(project, channel), params: { notification_channel: { name: "x", webhook_url: "" } }
      expect(channel.reload).to have_attributes(name: "x", webhook_url: slack_url)
    end

    it "replaces the URL when a new valid one is given" do
      new_url = "https://hooks.slack.com/services/T1/B1/newONE1"
      patch project_notification_channel_path(project, channel), params: { notification_channel: { webhook_url: new_url } }
      expect(channel.reload.webhook_url).to eq(new_url)
    end

    it "rejects an invalid new URL without echoing any URL and keeps the stored one" do
      bad = "https://evil.example.com/secretBAD1"
      patch project_notification_channel_path(project, channel), params: { notification_channel: { webhook_url: bad } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be a Slack incoming webhook URL", "hooks.slack.com/…/WXYZ")
      expect(response.body).not_to include("secretBAD1")
      expect(response.body).not_to include("abcdWXYZ")
      expect(channel.reload.webhook_url).to eq(slack_url)
    end

    it "ignores a webhook_url submitted for an email channel" do
      mail = create(:notification_channel, :email, project: project)
      patch project_notification_channel_path(project, mail), params: { notification_channel: { webhook_url: slack_url } }
      expect(mail.reload.webhook_url).to be_nil
    end

    it "ignores a kind change on update" do
      patch project_notification_channel_path(project, channel), params: { notification_channel: { kind: "email", name: "k" } }
      expect(channel.reload.kind).to eq("slack")
    end
  end

  describe "last delivery on the index" do
    let!(:channel) { create(:notification_channel, project: project) }

    it "shows never when there are no deliveries" do
      get project_notification_channels_path(project)
      expect(response.body).to include("never")
    end

    it "shows sent with a relative time" do
      channel.notification_deliveries.create!(kind: "test", events: [], status: "sent", sent_at: 5.minutes.ago)
      get project_notification_channels_path(project)
      expect(response.body).to match(/sent 5 minutes ago/)
    end

    it "shows the redacted error for a failed delivery, using the most recent" do
      channel.notification_deliveries.create!(kind: "test", events: [], status: "sent", sent_at: 1.hour.ago)
      channel.notification_deliveries.create!(kind: "test", events: [], status: "failed", last_error: "HTTP 404 from hooks.slack.com/…/WXYZ")
      get project_notification_channels_path(project)
      expect(response.body).to include("failed: HTTP 404 from hooks.slack.com/…/WXYZ")
    end

    it "shows pending" do
      channel.notification_deliveries.create!(kind: "test", events: [], status: "pending")
      get project_notification_channels_path(project)
      expect(response.body).to match(/Last delivery:\s*pending/)
    end
  end

  describe "Send test" do
    include ActiveJob::TestHelper

    let!(:channel) { create(:notification_channel, project: project, name: "#qa", webhook_url: slack_url) }

    it "sends and flashes success" do
      stub_request(:post, slack_url).to_return(status: 200)
      post test_project_notification_channel_path(project, channel)
      expect(response).to redirect_to(project_notification_channels_path(project))
      expect(flash[:notice]).to eq("Test sent to #qa")
      expect(channel.notification_deliveries.last).to have_attributes(kind: "test", status: "sent")
    end

    it "flashes a redacted failure on a permanent error" do
      stub_request(:post, slack_url).to_return(status: 404)
      post test_project_notification_channel_path(project, channel)
      delivery = channel.notification_deliveries.last
      expect(delivery.status).to eq("failed")
      expect(flash[:alert]).to eq("Test failed: #{delivery.last_error}")
      expect(flash[:alert]).not_to include("abcdWXYZ")
    end

    it "flashes (will retry) when the job schedules a retry" do
      stub_request(:post, slack_url).to_return(status: 500)
      post test_project_notification_channel_path(project, channel)
      delivery = channel.notification_deliveries.last
      expect(delivery.status).to eq("pending")
      expect(delivery.last_error).to be_present
      expect(flash[:alert]).to eq("Test failed: #{delivery.last_error} (will retry)")
      expect(DeliverNotificationJob).to have_been_enqueued
    end
  end

  describe "ownership" do
    let(:other_project) { create(:project) }
    let!(:channel) { create(:notification_channel, project: other_project) }

    it "returns 404 for every action on another user's project" do
      get project_notification_channels_path(other_project)
      expect(response).to have_http_status(:not_found)
      get new_project_notification_channel_path(other_project)
      expect(response).to have_http_status(:not_found)
      post project_notification_channels_path(other_project), params: create_params
      expect(response).to have_http_status(:not_found)
      get edit_project_notification_channel_path(other_project, channel)
      expect(response).to have_http_status(:not_found)
      patch project_notification_channel_path(other_project, channel), params: { notification_channel: { name: "x" } }
      expect(response).to have_http_status(:not_found)
      post test_project_notification_channel_path(other_project, channel)
      expect(response).to have_http_status(:not_found)
      delete project_notification_channel_path(other_project, channel)
      expect(response).to have_http_status(:not_found)
      expect(NotificationChannel.exists?(channel.id)).to be(true)
    end

    it "404s a channel id from a different project of the same owner" do
      mine = create(:project, owner: user)
      get edit_project_notification_channel_path(mine, channel)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "links to Notifications from the project page" do
    get project_path(project)
    expect(response.body).to include("Notifications", project_notification_channels_path(project))
  end

  context "without SMTP" do
    before { mail_disabled! }

    it "offers only Slack and Teams" do
      get project_notification_channels_path(project)
      expect(response.body).to include("Add Slack", "Add Teams")
      expect(response.body).not_to include("Add Email")
    end

    it "refuses to create an email channel" do
      post project_notification_channels_path(project),
           params: { notification_channel: { kind: "email", name: "Team", recipients: "a@example.com" } }
      expect(response).to have_http_status(:not_found)
      expect(project.notification_channels.where(kind: "email")).to be_empty
    end
  end
end
