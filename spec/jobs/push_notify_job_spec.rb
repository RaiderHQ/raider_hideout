require "rails_helper"

RSpec.describe PushNotifyJob do
  include ActiveJob::TestHelper

  let(:project) { create(:project, name: "Checkout") }
  let(:build) { create(:build, project: project, branch: "main", status: "failed", default_branch: "main", failed_count: 1) }
  let!(:result) { add_failed_result(build) }

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  # Runs notify + every send job it enqueued, with retries flushed in the same pass when asked.
  def run_pushes(attempt: 1)
    described_class.perform_now(build.id, attempt)
    perform_enqueued_jobs(only: PushSendJob)
  end

  def stub_push(endpoint, status: 201, **response)
    stub_request(:post, endpoint).to_return(status: status, **response)
  end

  it "POSTs once per subscribed device with a VAPID header and an encrypted body" do
    _, first = subscribe_member(project)
    _, second = subscribe_member(project)
    stubs = [ first, second ].map { |s| stub_push(s.endpoint) }

    run_pushes

    stubs.each do |stub|
      expect(stub).to have_been_requested.once
    end
    expect(WebMock).to have_requested(:post, first.endpoint).with { |req|
      req.headers["Authorization"].start_with?("vapid t=") &&
        req.headers["Content-Encoding"] == "aes128gcm" && req.headers["Urgency"] == "high" && req.headers["Ttl"] == "86400" &&
        req.body.bytesize > 100 && !req.body.include?("Checkout")
    }
  end

  it "sends nothing for a feature-branch failure" do
    subscribe_member(project)
    build.update!(branch: "feature/x")
    run_pushes
    expect(a_request(:post, /fcm/)).not_to have_been_made
  end

  it "sends nothing when the project is muted" do
    user, = subscribe_member(project)
    PushMutedProject.create!(user: user, project: project)
    run_pushes
    expect(a_request(:post, /fcm/)).not_to have_been_made
  end

  it "sends nothing to a user removed from the organization" do
    user, = subscribe_member(project)
    Membership.where(user: user).destroy_all
    run_pushes
    expect(a_request(:post, /fcm/)).not_to have_been_made
  end

  it "sends new_flaky only when opted in" do
    user, subscription = subscribe_member(project)
    passed = create(:build, project: project, branch: "main", status: "passed", default_branch: "main")
    create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "main", flaky: true, flaky_since_build: passed)
    stub = stub_push(subscription.endpoint)

    described_class.perform_now(passed.id)
    perform_enqueued_jobs(only: PushSendJob)
    expect(stub).not_to have_been_requested

    user.push_preference!.update!(new_flaky: true)
    described_class.perform_now(passed.id)
    perform_enqueued_jobs(only: PushSendJob)
    expect(stub).to have_been_requested.once
  end

  it "pushes the same build and attempt once, a new attempt again" do
    _, subscription = subscribe_member(project)
    stub = stub_push(subscription.endpoint)
    2.times { run_pushes }
    expect(stub).to have_been_requested.once
    expect(PushDelivery.count).to eq(1)

    run_pushes(attempt: 2)
    expect(stub).to have_been_requested.twice
  end

  it "records the success time on 201" do
    _, subscription = subscribe_member(project)
    stub_push(subscription.endpoint)
    expect { run_pushes }.to change { subscription.reload.last_success_at }.from(nil)
  end

  [ 410, 404 ].each do |status|
    it "deletes the subscription on #{status}" do
      _, subscription = subscribe_member(project)
      stub_push(subscription.endpoint, status: status)
      expect { run_pushes }.to change(PushSubscription, :count).by(-1)
      expect(PushSubscription.exists?(subscription.id)).to be(false)
    end
  end

  [ 401, 403 ].each do |status|
    it "keeps the subscription on #{status} and logs only ids" do
      _, subscription = subscribe_member(project)
      stub_push(subscription.endpoint, status: status, body: "secret-body")
      logged = capture_log { run_pushes }
      expect(PushSubscription.exists?(subscription.id)).to be(true)
      expect(logged).to include("subscription #{subscription.id}")
      [ subscription.endpoint, subscription.endpoint.split("/").last, subscription.p256dh, subscription.auth, "secret-body", "Checkout fails" ].each do |secret|
        expect(logged).not_to include(secret)
      end
    end
  end

  it "keeps the subscription on 413" do
    _, subscription = subscribe_member(project)
    stub_push(subscription.endpoint, status: 413)
    expect { run_pushes }.not_to change(PushSubscription, :count)
  end

  [ 301, 302 ].each do |status|
    it "treats a #{status} as a failure and never follows the redirect" do
      _, subscription = subscribe_member(project)
      target = "https://169.254.169.254/latest/meta-data"
      stub_push(subscription.endpoint, status: status, headers: { "Location" => target })
      stub_request(:post, target)
      stub_request(:get, target)

      expect { run_pushes }.not_to change(PushSubscription, :count)
      expect(a_request(:any, target)).not_to have_been_made
      expect(subscription.reload.last_success_at).to be_nil
      expect(enqueued_jobs.select { _1["job_class"] == "PushSendJob" }).to be_empty
    end
  end

  [ 429, 500, 503 ].each do |status|
    it "retries only that device on #{status} and keeps the subscription" do
      _, throttled = subscribe_member(project)
      _, healthy = subscribe_member(project)
      stub_push(throttled.endpoint, status: status)
      healthy_stub = stub_push(healthy.endpoint)

      run_pushes
      expect(PushSubscription.exists?(throttled.id)).to be(true)
      retries = enqueued_jobs.select { _1["job_class"] == "PushSendJob" }
      expect(retries.size).to eq(1)
      expect(retries.first["executions"]).to eq(1)

      perform_enqueued_jobs(only: PushSendJob)
      expect(healthy_stub).to have_been_requested.once
      expect(a_request(:post, throttled.endpoint)).to have_been_made.twice
    end
  end

  it "gives up after five executions" do
    _, subscription = subscribe_member(project)
    stub_push(subscription.endpoint, status: 503)
    described_class.perform_now(build.id)
    5.times { perform_enqueued_jobs(only: PushSendJob) }
    expect(a_request(:post, subscription.endpoint)).to have_been_made.times(5)
    expect(enqueued_jobs.select { _1["job_class"] == "PushSendJob" }).to be_empty
    expect(PushSubscription.exists?(subscription.id)).to be(true)
  end

  it "retries timeouts without leaking the endpoint" do
    _, subscription = subscribe_member(project)
    stub_request(:post, subscription.endpoint).to_timeout
    logged = capture_log { run_pushes }
    expect(enqueued_jobs.count { _1["job_class"] == "PushSendJob" }).to eq(1)
    expect(logged).not_to include(subscription.endpoint.split("/").last)
  end

  it "skips an endpoint that is no longer allowed" do
    _, subscription = subscribe_member(project)
    subscription.update_column(:endpoint, "https://10.0.0.1/push/abc")
    stub_request(:post, "https://10.0.0.1/push/abc")
    run_pushes
    expect(a_request(:any, /10\.0\.0\.1/)).not_to have_been_made
  end

  it "calls the push service with the stored VAPID subject" do
    _, subscription = subscribe_member(project)
    stub_push(subscription.endpoint)
    expect(WebPush).to receive(:payload_send).with(hash_including(vapid: hash_including(:subject, :public_key, :private_key))).and_call_original
    run_pushes
  end

  # Includes ActiveJob's own logger, which logs retries and arguments.
  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    originals = [ Rails.logger, ActiveJob::Base.logger ]
    Rails.logger = ActiveJob::Base.logger = logger
    yield
    io.string
  ensure
    Rails.logger, ActiveJob::Base.logger = originals
  end
end
