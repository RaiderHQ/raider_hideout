require "rails_helper"

RSpec.describe Notifications::HttpPost do
  let(:url) { "https://hooks.slack.com/services/T0/B0/abcd" }

  def retry_after_for(header)
    stub_request(:post, url).to_return(status: 429, headers: header)
    described_class.call(url, {})
  rescue Notifications::RetryableError => e
    e.retry_after
  end

  it "parses Retry-After seconds" do
    expect(retry_after_for("Retry-After" => "30")).to eq(30)
    expect(retry_after_for("Retry-After" => "999999")).to eq(3600)
  end

  it "parses Retry-After HTTP dates" do
    value = retry_after_for("Retry-After" => (Time.now + 120).httpdate)
    expect(value).to be_between(115, 121)
  end

  it "ignores garbage or missing Retry-After" do
    expect(retry_after_for("Retry-After" => "soon")).to be_nil
    expect(retry_after_for({})).to be_nil
  end

  it "does not follow redirects" do
    stub_request(:post, url).to_return(status: 302, headers: { "Location" => "https://evil.example/x" })
    expect { described_class.call(url, {}) }.to raise_error(Notifications::PermanentError)
    expect(a_request(:post, "https://evil.example/x")).not_to have_been_made
  end

  it "keeps the body out of the message and caps it in an attribute" do
    stub_request(:post, url).to_return(status: 400, body: "b" * 5000)
    expect { described_class.call(url, {}) }.to raise_error(Notifications::PermanentError) { |e|
      expect(e.message).to eq("HTTP 400")
      expect(e.body.length).to eq(4000)
    }
  end

  it "maps invalid URLs to a permanent error without the URL" do
    expect { described_class.call("http://bad host/secret", {}) }
      .to raise_error(Notifications::PermanentError, "invalid webhook URL")
  end
end
