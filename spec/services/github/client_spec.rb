require "rails_helper"

RSpec.describe Github::Client do
  let(:token) { "ghp_#{'a' * 36}" }
  let(:client) { described_class.new(token) }
  let(:url) { "https://api.github.com/repos/octo/hello" }
  let(:headers) do
    { "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github+json",
      "X-GitHub-Api-Version" => "2022-11-28", "User-Agent" => "Raider-Hideout" }
  end

  it "sends the four headers to the exact URL and returns the status" do
    stub = stub_request(:get, url).with(headers: headers).to_return(status: 200, body: '{"id":1}')
    expect(client.repository("octo", "hello")).to eq(Github::Response.new(status: 200, message: nil))
    expect(stub).to have_been_requested
  end

  it "uses 10 second timeouts and no retries" do
    stub_request(:get, url).to_return(status: 200)
    seen = nil
    allow(Net::HTTP).to receive(:new).and_wrap_original { |m, *a| (seen = m.call(*a)) }
    client.repository("octo", "hello")
    expect([ seen.open_timeout, seen.read_timeout, seen.write_timeout, seen.max_retries ]).to eq([ 10, 10, 10, 0 ])
    expect(seen.use_ssl?).to be(true)
  end

  it "does not follow redirects" do
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => "https://evil.example/steal" },
                                      body: '{"message":"Moved Permanently"}')
    evil = stub_request(:get, "https://evil.example/steal")
    expect(client.repository("octo", "hello")).to eq(Github::Response.new(status: 301, message: "Moved Permanently"))
    expect(evil).not_to have_been_requested
  end

  it "reads GitHub's JSON message only" do
    stub_request(:get, url).to_return(status: 401, body: '{"message":"Bad credentials","other":"x"}')
    expect(client.repository("octo", "hello").message).to eq("Bad credentials")
    stub_request(:get, url).to_return(status: 500, body: "<html>oops</html>")
    expect(client.repository("octo", "hello")).to eq(Github::Response.new(status: 500, message: nil))
    stub_request(:get, url).to_return(status: 500, body: '{"message":["a"]}')
    expect(client.repository("octo", "hello").message).to be_nil
  end

  it "redacts the token from the message, then truncates to 200 characters" do
    stub_request(:get, url).to_return(status: 401, body: { message: "x #{token} y" }.to_json)
    expect(client.repository("octo", "hello").message).to eq("x [token] y")

    padded = "#{'z' * 195}#{token}"
    stub_request(:get, url).to_return(status: 401, body: { message: padded }.to_json)
    message = client.repository("octo", "hello").message
    expect(message).to eq("#{'z' * 195}[token]"[0, 200])
    expect(message).not_to include("ghp_")
  end

  it "maps network failures to :network without leaking the token" do
    [ Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError, EOFError ].each do |error|
      stub_request(:get, url).to_raise(error.new("boom #{token}"))
      expect(client.repository("octo", "hello")).to eq(Github::Response.new(status: :network, message: nil))
    end
  end

  it "refuses an owner or repo that could change the path, without a request" do
    [ [ "..", "r" ], [ "o", "." ], [ "a/b", "r" ], [ "a b", "r" ], [ "o", "r?x=1" ], [ "o", "" ] ].each do |owner, repo|
      expect { client.repository(owner, repo) }.to raise_error(Github::Client::Error) { |e| expect(e.message).not_to include(token) }
    end
  end

  it "refuses a malformed token before any request" do
    stub = stub_request(:any, /api\.github\.com/)
    [ "ghp_short", "", nil, "ghp_#{'a' * 36}\n", "x y" ].each do |bad|
      expect { described_class.new(bad).repository("octo", "hello") }
        .to raise_error(Github::Client::Error, "invalid token")
    end
    expect(stub).not_to have_been_requested
  end

  it "masks token-shaped strings in the message" do
    stub_request(:get, url).to_return(status: 401, body: { message: "bad ghp_abcdefgh12" }.to_json)
    expect(client.repository("octo", "hello").message).to eq("bad [token]")
  end

  it "does not expose the token through inspect" do
    expect(client.inspect).not_to include(token)
  end

  describe "#rerun_failed_jobs" do
    let(:rerun_url) { "https://api.github.com/repos/octo/hello/actions/runs/123/rerun-failed-jobs" }

    it "POSTs the exact URL with an empty body and returns the status" do
      stub = stub_request(:post, rerun_url).with(headers: headers, body: "").to_return(status: 201, body: "")
      expect(client.rerun_failed_jobs("octo", "hello", "123")).to eq(Github::Response.new(status: 201, message: nil))
      expect(stub).to have_been_requested
    end

    it "refuses a bad token, repository or run id without a request" do
      stub = stub_request(:any, /api\.github\.com/)
      expect { described_class.new("nope").rerun_failed_jobs("octo", "hello", "123") }.to raise_error(Github::Client::Error, "invalid token")
      [ [ "..", "r", "1" ], [ "o", "r/x", "1" ], [ "o", "r", "1/../2" ], [ "o", "r", "1" * 21 ], [ "o", "r", "%2F" ], [ "o", "r", "" ] ].each do |o, r, id|
        expect { client.rerun_failed_jobs(o, r, id) }.to raise_error(Github::Client::Error)
      end
      expect(stub).not_to have_been_requested
    end
  end

  describe "#workflow" do
    let(:workflow_url) { "https://api.github.com/repos/octo/hello/actions/workflows/test_pipeline.yml" }

    it "GETs the exact URL and returns the status" do
      stub = stub_request(:get, workflow_url).with(headers: headers).to_return(status: 200, body: '{"id":7}')
      expect(client.workflow("octo", "hello", "test_pipeline.yml")).to eq(Github::Response.new(status: 200, message: nil))
      expect(stub).to have_been_requested
    end

    it "refuses a workflow or repository that could change the path, without a request" do
      stub = stub_request(:any, /api\.github\.com/)
      [ [ "o", "r", "../x.yml" ], [ "o", "r", "a/x.yml" ], [ "o", "r", "x%2F.yml" ], [ "o", "r", "x.yml/.." ], [ "o", "r", "x" ],
        [ "..", "r", "x.yml" ], [ "o", "r", nil ], [ "o", "r", "x.yml\nfoo" ], [ "o\n", "r", "x.yml" ] ].each do |o, r, w|
        expect { client.workflow(o, r, w) }.to raise_error(Github::Client::Error)
      end
      expect(stub).not_to have_been_requested
    end
  end

  describe "#dispatch_workflow" do
    let(:dispatch_url) { "https://api.github.com/repos/octo/hello/actions/workflows/test_pipeline.yml/dispatches" }
    let(:json_headers) { headers.merge("Content-Type" => "application/json") }

    def dispatch(ref: "main", inputs: {}, owner: "octo", repo: "hello", workflow: "test_pipeline.yml")
      client.dispatch_workflow(owner, repo, workflow, ref: ref, inputs: inputs)
    end

    it "POSTs the ref and return_run_details as JSON, with no inputs key when there are none" do
      stub = stub_request(:post, dispatch_url).with(headers: json_headers) { |req|
        JSON.parse(req.body) == { "ref" => "main", "return_run_details" => true }
      }.to_return(status: 204, body: "")
      expect(dispatch).to eq(Github::Response.new(status: 204, message: nil, run_id: nil, html_url: nil))
      expect(stub).to have_been_requested
    end

    it "sends the one tag input when given" do
      stub = stub_request(:post, dispatch_url).with { |req|
        JSON.parse(req.body) == { "ref" => "release/1.2", "return_run_details" => true, "inputs" => { "tags" => "@smoke, @fast" } }
      }.to_return(status: 204)
      dispatch(ref: "release/1.2", inputs: { "tags" => "@smoke, @fast" })
      expect(stub).to have_been_requested
    end

    it "reads the run id and html_url from a 200" do
      stub_request(:post, dispatch_url).to_return(
        status: 200, body: { workflow_run_id: 123, run_url: "x", html_url: "https://github.com/octo/hello/actions/runs/123" }.to_json
      )
      expect(dispatch).to eq(Github::Response.new(status: 200, message: nil, run_id: "123",
                                                  html_url: "https://github.com/octo/hello/actions/runs/123"))
    end

    it "keeps an attempt page" do
      stub_request(:post, dispatch_url).to_return(
        status: 200, body: { workflow_run_id: 9, html_url: "https://github.com/octo/hello/actions/runs/9/attempts/1" }.to_json
      )
      expect(dispatch.html_url).to eq("https://github.com/octo/hello/actions/runs/9/attempts/1")
    end

    it "keeps GitHub's casing of the same repository" do
      stub_request(:post, dispatch_url).to_return(
        status: 200, body: { workflow_run_id: 9, html_url: "https://github.com/Octo/Hello/actions/runs/9" }.to_json
      )
      expect(dispatch.html_url).to eq("https://github.com/Octo/Hello/actions/runs/9")
    end

    it "trusts no run id that is not a small positive integer" do
      [ "123", -1, 10**24, 1.5, nil, true ].each do |bad|
        stub_request(:post, dispatch_url).to_return(status: 200, body: { workflow_run_id: bad, html_url: "https://github.com/octo/hello/actions/runs/123" }.to_json)
        expect(dispatch).to have_attributes(status: 200, run_id: nil, html_url: nil), bad.inspect
      end
    end

    it "rebuilds an html_url that points anywhere else" do
      [ "https://evil.example/octo/hello/actions/runs/123", "https://github.com/octo/hello/actions/runs/1234",
        "https://github.com/other/hello/actions/runs/123", "https://github.com/octo/hello/actions/runs/123\"><x>",
        "javascript:alert(1)", nil, 42, "https://github.com/octo/hello/actions/runs/123/../../../../evil/repo",
        "httpſ://github.com/octo/hello/actions/runs/123", "https://github.com/octo/hello/actionſ/runs/123",
        "https://github.com/octo/hello/actions/runs/123/job/5" ].each do |bad|
        stub_request(:post, dispatch_url).to_return(status: 200, body: { workflow_run_id: 123, html_url: bad }.to_json)
        expect(dispatch.html_url).to eq("https://github.com/octo/hello/actions/runs/123"), bad.inspect
      end
    end

    it "ignores a run id in an error answer and keeps the message" do
      stub_request(:post, dispatch_url).to_return(status: 422, body: { message: "No ref found for: x", workflow_run_id: 5 }.to_json)
      expect(dispatch).to eq(Github::Response.new(status: 422, message: "No ref found for: x", run_id: nil, html_url: nil))
    end

    it "maps a network failure" do
      stub_request(:post, dispatch_url).to_timeout
      expect(dispatch).to eq(Github::Response.new(status: :network, message: nil))
    end

    it "refuses bad parts, refs and inputs without a request" do
      stub = stub_request(:any, /api\.github\.com/)
      bad = [
        { owner: ".." }, { repo: "a/b" }, { workflow: "../x.yml" }, { workflow: "x.yml/.." }, { workflow: "x%2F.yml" },
        { ref: "a..b" }, { ref: "a//b" }, { ref: "a@{1}" }, { ref: "-x" }, { ref: "x" * 201 }, { ref: "a.lock" }, { ref: "a/" },
        { ref: "a." }, { ref: "a b" }, { ref: "a\nb" }, { ref: "" }, { ref: nil },
        { inputs: { "tags" => "a\"b" } }, { inputs: { "tags" => "a\nb" } }, { inputs: { "tags" => "" } },
        { inputs: { "ta/gs" => "x" } }, { inputs: { "tags" => "x", "browser" => "y" } }, { inputs: { tags: "x" } }, { inputs: "x" }
      ]
      bad.each do |args|
        expect { dispatch(**args) }.to raise_error(Github::Client::Error), args.inspect
      end
      expect(stub).not_to have_been_requested
    end
  end
end
