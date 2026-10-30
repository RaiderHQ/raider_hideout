require "rails_helper"

RSpec.describe Notifications::TeamsNotifier do
  let(:channel) { create(:notification_channel, :teams) }
  let(:url) { channel.webhook_url }
  let(:notifier) { described_class.new(channel) }
  let(:message) do
    Notifications::Message.new(title: "Raider: build failed — Shop", headline: "build failed",
                               summary: "1 failed, 2 passed, 0 skipped (3s)", project_name: "Shop",
                               branch: "main", commit: "abcdef1 Fix", failures: [ "a (spec/a_spec.rb)" ],
                               new_flaky: [ "flaky" ], pass_rate: 67,
                               build_url: "http://example.com/b", pr_url: "https://github.com/o/r/pull/1")
  end

  it "posts an adaptive card and accepts 202" do
    body = nil
    stub_request(:post, url).with { |req| body = JSON.parse(req.body) }.to_return(status: 202)
    expect(notifier.deliver(message)).to be_nil
    expect(body["type"]).to eq("message")
    attachment = body["attachments"][0]
    expect(attachment["contentType"]).to eq("application/vnd.microsoft.card.adaptive")
    card = attachment["content"]
    expect(card).to include("type" => "AdaptiveCard", "version" => "1.4")
    expect(card["body"][0]["inlines"][0]).to include("type" => "TextRun", "text" => message.title)
    texts = card["body"].flat_map { |b| b["inlines"].to_a }.map { |i| i["text"] }
    expect(texts).to include("Branch: main", "Commit: abcdef1 Fix")
    facts = card["body"].find { |b| b["type"] == "FactSet" }["facts"]
    expect(facts).to eq([ { "title" => "Pass rate", "value" => "67%" } ])
    expect(card["actions"][0]).to include("type" => "Action.OpenUrl", "url" => "http://example.com/b")
    expect(card["actions"].size).to eq(2)
  end

  it "omits actions for unsafe URLs" do
    bad = message.with(build_url: "javascript:alert(1)", pr_url: nil)
    expect(notifier.payload(bad)[:attachments][0][:content][:actions]).to eq([])
  end

  it "renders hostile strings only inside TextRun.text" do
    hostile = message.with(failures: [ "[Click](https://evil) **x**" ])
    card = notifier.payload(hostile)[:attachments][0][:content]
    expect(card[:body].select { |b| b[:type] == "TextBlock" }).to be_empty
    runs = card[:body].flat_map { |b| b[:inlines].to_a }
    expect(runs.map { |r| r[:text] }).to include("[Click](https://evil) **x**")
    expect(card[:version]).to eq("1.4")
  end

  it_behaves_like "a webhook notifier"
end
