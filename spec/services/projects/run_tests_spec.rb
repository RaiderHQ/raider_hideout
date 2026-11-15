require "rails_helper"

RSpec.describe Projects::RunTests do
  include ActiveSupport::Testing::TimeHelpers

  let(:token) { "ghp_#{'a' * 36}" }
  let(:organization) { create(:organization) }
  let(:project) { create(:project, organization: organization) }
  let(:user) { create(:user).tap { |u| create(:membership, organization: organization, user: u, role: "member") } }
  let(:admin) { create(:user).tap { |u| create(:membership, organization: organization, user: u, role: "admin") } }
  let!(:access) do
    CiAccess.create!(project: project, token: token, token_saved_at: Time.current,
                     repository: "acme/shop-tests", workflow: "test_pipeline.yml", tag_input: "tags")
  end
  let(:url) { "https://api.github.com/repos/acme/shop-tests/actions/workflows/test_pipeline.yml/dispatches" }
  let(:any_request) { stub_request(:any, /api\.github\.com/) }
  let(:run_body) { { workflow_run_id: 123, html_url: "https://github.com/acme/shop-tests/actions/runs/123" }.to_json }

  def call(ref: "main", tags: nil, as: user) = described_class.call(project: project, user: as, ref: ref, tags: tags)

  describe "when Run tests is not set up" do
    it "tells admins to set it up and members to ask, with no row and no request" do
      access.update!(workflow: nil)
      any_request
      expect(call(as: admin)).to have_attributes(ok: false, message: "Set up Run tests in CI access.", request: nil)
      expect(call).to have_attributes(ok: false, message: "Ask an admin to set up Run tests in CI access.", request: nil)
      access.destroy
      expect(described_class.call(project: Project.find(project.id), user: user, ref: "main", tags: nil).message)
        .to eq("Ask an admin to set up Run tests in CI access.")
      expect(any_request).not_to have_been_requested
      expect(RunRequest.count).to eq(0)
    end
  end

  it "refuses a bad ref or bad tags with the copy, no row and no request" do
    any_request
    [ "a..b", "-x", "a//b", "a@{1}", "x" * 201, "a.lock", "", "  ", "a b" ].each do |ref|
      expect(call(ref: ref)).to have_attributes(ok: false, message: "Enter a branch or tag name.", request: nil), ref.inspect
    end
    [ "a\"b", "a\nb", "x" * 201, "<b>", "a:b:c", "a:", ", ," ].each do |tags|
      expect(call(tags: tags)).to have_attributes(ok: false, message: "Use letters, numbers, @, :, commas and spaces."), tags.inspect
    end
    expect(any_request).not_to have_been_requested
    expect(RunRequest.count).to eq(0)
  end

  it "starts the workflow and records the run" do
    stub = stub_request(:post, url).with { |req|
      JSON.parse(req.body) == { "ref" => "main", "return_run_details" => true, "inputs" => { "tags" => "@smoke" } }
    }.to_return(status: 200, body: run_body)
    outcome = call(ref: " main ", tags: " @smoke ")
    expect(stub).to have_been_requested.once
    expect(outcome).to have_attributes(ok: true, message: "Tests requested on main. Results appear in Builds when the run uploads them.")
    expect(outcome.request.reload).to have_attributes(
      project: project, user: user, ref: "main", tags: "@smoke", repository: "acme/shop-tests", workflow: "test_pipeline.yml",
      status: "accepted", http_status: 200, message: nil, github_run_id: "123",
      html_url: "https://github.com/acme/shop-tests/actions/runs/123"
    )
  end

  it "sends no inputs without tags, and ignores tags when no tag input is set" do
    bodies = []
    stub_request(:post, url).with { |req| bodies << JSON.parse(req.body) }.to_return(status: 204)
    call(tags: "  ")
    access.update!(tag_input: nil)
    expect(call(ref: "dev", tags: "@smoke").request.tags).to be_nil
    expect(bodies).to eq([ { "ref" => "main", "return_run_details" => true }, { "ref" => "dev", "return_run_details" => true } ])
  end

  it "accepts a 204 with no run id" do
    stub_request(:post, url).to_return(status: 204)
    outcome = call
    expect(outcome.ok).to be(true)
    expect(outcome.request).to have_attributes(status: "accepted", http_status: 204, github_run_id: nil, html_url: nil)
  end

  {
    401 => [ "rejected", "GitHub rejected the token. Replace it in CI access." ],
    403 => [ "rejected", "GitHub refused: the token needs Actions: Read and write for this repository." ],
    404 => [ "rejected", "GitHub can't find this workflow, or the token can't see the repository. Check CI access." ],
    429 => [ "failed", "GitHub is busy. Try again in a minute." ],
    500 => [ "failed", "GitHub is busy. Try again in a minute." ]
  }.each do |code, (status, copy)|
    it "records a #{code} as #{status} with the copy" do
      stub_request(:post, url).to_return(status: code, body: { message: "nope #{token}" }.to_json)
      outcome = call
      expect(outcome).to have_attributes(ok: false, message: copy)
      expect(outcome.request).to have_attributes(status: status, http_status: code, message: "nope [token]")
      expect(outcome.request.state_copy).to eq(copy)
    end
  end

  it "shows GitHub's 422 message, redacted and truncated" do
    stub_request(:post, url).to_return(status: 422, body: { message: "No ref found for: x ghp_abcdefgh12 #{'z' * 300}" }.to_json)
    outcome = call
    expect(outcome.request).to have_attributes(status: "rejected", http_status: 422)
    expect(outcome.request.message.length).to eq(200)
    expect(outcome.request.message).to start_with("No ref found for: x [token] zzz")
    expect(outcome.message).to eq("GitHub refused the run: #{outcome.request.message}")
    expect(outcome.message).not_to include(token)
  end

  it "masks a short token prefix GitHub echoes" do
    stub_request(:post, url).to_return(status: 401, body: { message: "Bad credentials ghp_abc1" }.to_json)
    expect(call.request.message).to eq("Bad credentials [token]")
  end

  it "treats a stored token that fails the client's check as rejected, with the same copy in the panel" do
    client = instance_double(Github::Client)
    allow(client).to receive(:dispatch_workflow).and_raise(Github::Client::Error, "invalid token")
    allow(Github::Client).to receive(:new).and_return(client)
    outcome = call
    expect(outcome).to have_attributes(ok: false, message: "GitHub rejected the token. Replace it in CI access.")
    expect(outcome.request).to have_attributes(status: "rejected", http_status: nil)
    expect(outcome.request.state_copy).to eq("GitHub rejected the token. Replace it in CI access.")
  end

  it "explains a 422 without a message" do
    stub_request(:post, url).to_return(status: 422, body: "")
    expect(call.message).to eq("GitHub refused the run. Check the branch or tag and the workflow's inputs.")
  end

  it "records a network failure" do
    stub_request(:post, url).to_timeout
    outcome = call
    expect(outcome).to have_attributes(ok: false, message: "Couldn't reach GitHub.")
    expect(outcome.request).to have_attributes(status: "failed", http_status: nil)
  end

  it "rebuilds an html_url on another host" do
    stub_request(:post, url).to_return(status: 200, body: { workflow_run_id: 123, html_url: "https://evil.example/x" }.to_json)
    expect(call.request.html_url).to eq("https://github.com/acme/shop-tests/actions/runs/123")
  end

  it "calls GitHub outside any database transaction" do
    baseline = ActiveRecord::Base.connection.open_transactions
    seen = nil
    stub_request(:post, url).to_return do
      seen = ActiveRecord::Base.connection.open_transactions
      { status: 204 }
    end
    expect(call.ok).to be(true)
    expect(seen).to eq(baseline)
  end

  describe "the double-tap guard" do
    before { stub_request(:post, url).to_return(status: 204) }

    it "refuses the same ref and tags within 60 seconds without a request" do
      travel_to(Time.zone.parse("2026-11-15 09:41:10")) { call(tags: "@smoke") }
      travel_to(Time.zone.parse("2026-11-15 09:41:50")) do
        expect(call(ref: " main", tags: "@smoke ")).to have_attributes(ok: false, message: "Tests on main were already requested at 09:41.", request: nil)
      end
      expect(a_request(:post, url)).to have_been_made.once
    end

    it "treats blank and missing tags as the same request" do
      call(tags: nil)
      expect(call(tags: "  ").message).to start_with("Tests on main were already requested")
    end

    it "allows other tags, another ref, or the same request after 60 seconds" do
      travel_to(Time.zone.parse("2026-11-15 09:41:10")) { call(tags: "@smoke") }
      travel_to(Time.zone.parse("2026-11-15 09:41:20")) do
        expect(call(tags: "@fast").ok).to be(true)
        expect(call(ref: "dev", tags: "@smoke").ok).to be(true)
      end
      travel_to(Time.zone.parse("2026-11-15 09:42:11")) { expect(call(tags: "@smoke").ok).to be(true) }
    end

    it "does not count rejected or failed requests" do
      stub_request(:post, url).to_return(status: 401)
      call
      stub_request(:post, url).to_return(status: 204)
      expect(call.ok).to be(true)
    end
  end

  describe "the hourly cap" do
    before { stub_request(:post, url).to_return(status: 204) }

    it "refuses the 11th pending or accepted request in an hour without a request" do
      start = Time.zone.parse("2026-11-15 09:00:00")
      10.times { |i| travel_to(start + (i * 2).minutes) { expect(call(ref: "b#{i}").ok).to be(true) } }
      travel_to(start + 30.minutes) do
        expect(call(ref: "b11")).to have_attributes(ok: false, message: "This project already started 10 runs in the last hour. Try again later.")
      end
      expect(a_request(:post, url)).to have_been_made.times(10)
      travel_to(start + 61.minutes) { expect(call(ref: "b12").ok).to be(true) }
    end

    it "does not count rejected or failed requests, or other projects" do
      other = create(:project, organization: organization)
      10.times { |i| RunRequest.create!(project: other, ref: "x#{i}", repository: "a/b", workflow: "x.yml", status: "accepted") }
      %w[rejected failed].each { |status| 5.times { |i| RunRequest.create!(project: project, ref: "#{status}#{i}", repository: "a/b", workflow: "x.yml", status: status) } }
      expect(call.ok).to be(true)
    end
  end
end
