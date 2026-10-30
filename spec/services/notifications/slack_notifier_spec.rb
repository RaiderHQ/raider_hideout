require "rails_helper"

RSpec.describe Notifications::SlackNotifier do
  let(:channel) { create(:notification_channel, :slack) }
  let(:url) { channel.webhook_url }
  let(:notifier) { described_class.new(channel) }
  let(:message) do
    Notifications::Message.new(title: "Raider: build failed — Shop", headline: "build failed",
                               summary: "1 failed, 2 passed, 0 skipped (3s)", project_name: "Shop",
                               branch: "main", commit: "abcdef1 Fix", failures: [ "a (spec/a_spec.rb)" ],
                               new_flaky: [ "flaky" ], pass_rate: 67,
                               build_url: "http://example.com/b", pr_url: "https://github.com/o/r/pull/1")
  end

  it "posts blocks" do
    body = nil
    stub_request(:post, url).with { |req| body = JSON.parse(req.body) }.to_return(status: 200)
    expect(notifier.deliver(message)).to be_nil
    expect(body["text"]).to eq("Raider: build failed — Shop — 1 failed, 2 passed, 0 skipped (3s)")
    types = body["blocks"].map { |b| b["type"] }
    expect(types).to eq(%w[header section section section actions])
    expect(body["blocks"][1]["text"]["text"]).to include("1 failed", "main", "abcdef1 Fix")
    buttons = body["blocks"].last["elements"]
    expect(buttons.map { |b| b["text"]["text"] }).to eq([ "View build", "Pull request" ])
    expect(buttons.first["url"]).to eq("http://example.com/b")
  end

  it "omits the pull request button and empty sections" do
    plain = message.with(pr_url: nil, failures: [], new_flaky: [])
    body = notifier.payload(plain)
    expect(body[:blocks].map { |b| b[:type] }).to eq(%w[header section actions])
    expect(body[:blocks].last[:elements].size).to eq(1)
  end

  it "escapes hostile strings" do
    hostile = message.with(failures: [ "<!channel> <script>x</script> & *b*" ])
    json = JSON.generate(JSON.parse(notifier.payload(hostile).to_json))
    expect(json).to include("&lt;!channel&gt; &lt;script&gt;", "&amp;")
    expect(json).not_to include("<!channel>")
  end

  it "bounds section text and header length" do
    big = message.with(title: "T" * 400, failures: Array.new(5) { "<" * 1000 }, new_flaky: Array.new(5) { "x" * 1000 })
    blocks = notifier.payload(big)[:blocks]
    expect(blocks.first[:text][:text].length).to eq(150)
    expect(blocks.select { |b| b[:type] == "section" }.map { |b| b[:text][:text].length }).to all(be <= 3000)
  end

  it "omits invalid button urls" do
    bad = message.with(pr_url: "https://x.com/a b", build_url: "javascript:alert(1)")
    expect(notifier.payload(bad)[:blocks].last[:elements]).to eq([])
    long = message.with(pr_url: "https://x.com/#{'a' * 3000}")
    expect(notifier.payload(long)[:blocks].last[:elements].size).to eq(1)
  end

  it_behaves_like "a webhook notifier"
end
