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

  it "does not expose the token through inspect" do
    expect(client.inspect).not_to include(token)
  end
end
