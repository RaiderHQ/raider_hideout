require "rails_helper"

RSpec.describe "notifications e2e" do
  include ActiveJob::TestHelper
  let(:project) { create(:project) }
  let!(:slack) { create(:notification_channel, :slack, project: project) }
  let!(:teams) { create(:notification_channel, :teams, project: project) }
  let!(:email) { create(:notification_channel, :email, project: project) }

  before do
    stub_request(:post, /hooks.slack.com/).to_return(status: 200)
    stub_request(:post, /logic.azure.com/).to_return(status: 200)
    ActiveJob::Base.queue_adapter = :test
  end

  def shard(index, key:, status: "passed", branch: "main", total: 2)
    d = build_payload(results: [ build_result("identifier" => "x#{index}", "full_name" => "T#{index} <!channel>", "status" => status) ])
    d["run"]["ci"].merge!("build_key" => key)
    d["run"]["shard"] = { "index" => index, "total" => total, "label" => "s#{index}" }
    d["run"]["git"]["branch"] = branch
    d
  end

  def drain = 4.times { perform_enqueued_jobs }
  def ingest(d) = Ingest.call(project: project, payload: d.to_json, files: {})

  it "sends exactly once per channel, out of order, late shard, recovered, feature silent" do
    # shard 2 first, jobs interleaved: both ingested before any flakiness job runs
    ingest(shard(2, key: "k1", status: "failed"))
    ingest(shard(1, key: "k1"))
    drain
    expect(WebMock).to have_requested(:post, /hooks.slack.com/).once
    expect(WebMock).to have_requested(:post, /logic.azure.com/).once
    expect(ActionMailer::Base.deliveries.size).to eq 1
    body = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.find { |s| s.uri.host == "hooks.slack.com" }.body
    expect(body).not_to include("<!channel>")
    # late third shard
    ingest(shard(3, key: "k1", status: "failed"))
    drain
    expect(WebMock).to have_requested(:post, /hooks.slack.com/).once
    # passing build -> recovered
    ingest(shard(1, key: "k2")); ingest(shard(2, key: "k2"))
    drain
    expect(WebMock).to have_requested(:post, /hooks.slack.com/).twice
    expect(NotificationDelivery.where(kind: "build").last.events).to eq %w[recovered]
    # feature branch failing -> silent
    ingest(shard(1, key: "k3", status: "failed", branch: "feature/x", total: 1))
    drain
    expect(WebMock).to have_requested(:post, /hooks.slack.com/).twice
    expect(NotificationDelivery.where(status: "sent").count).to eq 6
  end

  it "notifies once when the second shard's job runs first (interleaved)" do
    ingest(shard(1, key: "k9", status: "failed"))
    first = enqueued_jobs.dup; clear_enqueued_jobs
    ingest(shard(2, key: "k9"))
    perform_enqueued_jobs(only: FlakinessJob); drain
    expect(NotificationDelivery.count).to eq 0
    first.each { |j| ActiveJob::Base.execute(j) } # shard 1 job
    drain
    expect(NotificationDelivery.where(status: "sent").count).to eq 3
  end
end
