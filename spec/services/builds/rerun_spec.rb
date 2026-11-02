require "rails_helper"

RSpec.describe Builds::Rerun do
  include ActiveSupport::Testing::TimeHelpers

  let(:token) { "ghp_#{'a' * 36}" }
  let(:project) { create(:project) }
  let(:user) { create(:user) }
  let!(:access) { CiAccess.create!(project: project, token: token, token_saved_at: Time.current) }
  let(:build_record) do
    create(:build, project: project, provider: "github_actions", status: "failed",
                   ci_run_key: "github_actions:octo/hello:123", latest_attempt: 2)
  end
  let(:url) { "https://api.github.com/repos/octo/hello/actions/runs/123/rerun-failed-jobs" }
  let(:any_request) { stub_request(:any, /api\.github\.com/) }

  def call = described_class.call(build: build_record, user: user)

  it "answers 'can't be re-run' without a request when not rerunnable" do
    build_record.update!(status: "passed")
    any_request
    outcome = call
    expect(outcome).to have_attributes(ok: false, message: "This build can't be re-run from Hideout.", rerun: nil)
    expect(any_request).not_to have_been_requested
  end

  it "answers the no-token copy, not the other, when only the token is missing" do
    access.destroy
    any_request
    expect(Build.find(build_record.id).then { |b| described_class.call(build: b, user: user) })
      .to have_attributes(ok: false, message: "Add a GitHub token in CI access first.")
    expect(any_request).not_to have_been_requested
  end

  it "never requests with a path-injecting key" do
    build_record.update_columns(ci_run_key: "github_actions:octo/..:123")
    any_request
    expect(call.message).to eq("This build can't be re-run from Hideout.")
    expect(any_request).not_to have_been_requested
  end

  it "accepts on 201, records attempt_before and uses attempt + 1 in the message" do
    stub = stub_request(:post, url).to_return(status: 201, body: "")
    outcome = call
    expect(stub).to have_been_requested.once
    expect(outcome).to have_attributes(ok: true, message: "Re-run requested. The result arrives as attempt 3.")
    expect(outcome.rerun).to have_attributes(status: "accepted", http_status: 201, attempt_before: 2, user: user, build: build_record)
  end

  {
    401 => [ "rejected", "GitHub rejected the token. Replace it in CI access." ],
    403 => [ "rejected", "GitHub refused: the token needs Actions: Read and write for this repository." ],
    404 => [ "rejected", "GitHub can't find this run, or the token can't see the repository." ],
    409 => [ "rejected", "GitHub can't re-run this run now (it may still be running or be too old)." ],
    422 => [ "rejected", "GitHub can't re-run this run now (it may still be running or be too old)." ],
    429 => [ "failed", "GitHub is busy. Try again in a minute." ],
    301 => [ "failed", "GitHub is busy. Try again in a minute." ],
    500 => [ "failed", "GitHub is busy. Try again in a minute." ]
  }.each do |code, (status, copy)|
    it "maps #{code} to #{status}" do
      stub_request(:post, url).to_return(status: code, body: '{"message":"nope"}')
      outcome = call
      expect(outcome).to have_attributes(ok: false, message: copy)
      expect(outcome.rerun).to have_attributes(status: status, http_status: code, message: "nope", attempt_before: 2)
    end
  end

  it "maps a network failure to failed with no http_status" do
    stub_request(:post, url).to_raise(Net::OpenTimeout)
    outcome = call
    expect(outcome).to have_attributes(ok: false, message: "Couldn't reach GitHub.")
    expect(outcome.rerun).to have_attributes(status: "failed", http_status: nil, message: nil)
  end

  it "stores the message redacted and at most 200 characters" do
    stub_request(:post, url).to_return(status: 401, body: { message: "Bad credentials #{token}" }.to_json)
    expect(call.rerun.message).to eq("Bad credentials [token]")
    stub_request(:post, url).to_return(status: 401, body: { message: "y" * 500 }.to_json)
    travel_to(11.minutes.from_now) { expect(call.rerun.message.length).to eq(200) }
  end

  it "calls GitHub with no transaction open" do
    baseline = ActiveRecord::Base.connection.open_transactions
    seen = nil
    stub_request(:post, url).to_return { seen = ActiveRecord::Base.connection.open_transactions; { status: 201 } }
    call
    expect(seen).to eq(baseline)
  end

  it "marks the row failed and re-raises on an unexpected error" do
    allow_any_instance_of(Github::Client).to receive(:rerun_failed_jobs).and_raise(RuntimeError, "boom")
    expect { call }.to raise_error(RuntimeError, "boom")
    expect(build_record.reruns.last).to have_attributes(status: "failed", message: nil)
  end

  it "treats a malformed stored token as a rejected credential" do
    access.update_column(:token, "garbage")
    any_request
    outcome = call
    expect(outcome).to have_attributes(ok: false, message: "GitHub rejected the token. Replace it in CI access.")
    expect(outcome.rerun).to have_attributes(status: "failed")
    expect(any_request).not_to have_been_requested
  end

  describe "guard" do
    before { stub_request(:post, url).to_return(status: 201) }

    it "blocks a second re-run within 10 minutes with no second request" do
      call
      outcome = call
      expect(outcome).to have_attributes(ok: false, rerun: nil)
      expect(outcome.message).to match(/\AA re-run was already requested at \d\d:\d\d\.\z/)
      expect(a_request(:post, url)).to have_been_made.once
    end

    it "blocks while a pending row exists" do
      build_record.reruns.create!(attempt_before: 2, status: "pending")
      expect(call).to have_attributes(ok: false, rerun: nil)
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "allows another after 10 minutes" do
      call
      travel_to(11.minutes.from_now) { expect(call.ok).to be(true) }
      expect(a_request(:post, url)).to have_been_made.twice
    end

    it "allows another once latest_attempt has moved" do
      call
      build_record.update!(latest_attempt: 3)
      expect(call.ok).to be(true)
    end

    it "is not triggered by a rejected earlier request" do
      stub_request(:post, url).to_return(status: 403).then.to_return(status: 201)
      expect(call.ok).to be(false)
      expect(call.ok).to be(true)
    end
  end
end
