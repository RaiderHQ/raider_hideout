require "rails_helper"

RSpec.describe SentryScrubber do
  let(:request) do
    Struct.new(:url, :headers, :data, :cookies).new(
      "https://raider.example.com/api/v1/runs",
      { "Authorization" => "Bearer rdr_secret", "cookie" => "session_id=abc",
        "Referer" => "https://raider.example.com/password_resets/tok123/edit", "User-Agent" => "raider_reporter/0.7.0" },
      { "payload" => "{\"results\":[]}" },
      { "session_id" => "abc" }
    )
  end
  let(:event) { Struct.new(:request).new(request) }

  it "drops credentials and the body, keeping the rest of the request" do
    expect(described_class.call(event, {})).to be(event)
    expect(request.headers).to eq("User-Agent" => "raider_reporter/0.7.0")
    expect(request.data).to be_nil
    expect(request.cookies).to be_nil
    expect(request.url).to eq("https://raider.example.com/api/v1/runs")
  end

  it "passes events without a request through untouched" do
    bare = Struct.new(:request).new(nil)
    expect(described_class.call(bare, {})).to be(bare)
  end
end
