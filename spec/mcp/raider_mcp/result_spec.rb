require "rails_helper"

RSpec.describe RaiderMcp::Result do
  def texts(response) = response.content.map { |part| part[:text] }

  it "returns the summary and the JSON as two text parts and as structured content" do
    payload = { data: [ { id: 1 } ], meta: { page: 1, per_page: 50, total: 1, next_page: nil } }

    response = described_class.ok("1 build", payload, list_key: :data)

    expect(texts(response)).to eq([ "1 build", JSON.generate(payload) ])
    expect(response.structured_content).to eq(payload)
    expect(response.error?).to be(false)
  end

  it "cuts a long page so all text stays within 50,000 characters, and says to ask for a smaller per_page" do
    items = Array.new(100) { |i| { id: i, message: "x" * 1_000 } }
    payload = { data: items, meta: { page: 2, per_page: 100, total: 250, next_page: 3 } }

    summary, json = texts(described_class.ok("Builds", payload, list_key: :data))

    expect(summary.length + json.length).to be <= 50_000
    shown = JSON.parse(json)["data"].size
    expect(shown).to be_between(40, 49)
    expect(summary).to eq("Builds showing #{shown} of 250; page cut to fit, pass a smaller per_page")
    expect(JSON.parse(json)["meta"]).to eq("page" => 2, "per_page" => 100, "total" => 250, "next_page" => 3)
  end

  it "builds a callable summary from the cut payload, so it names only the items returned" do
    items = Array.new(100) { |i| { id: i, message: "x" * 1_000 } }
    payload = { data: items, meta: { page: 1, per_page: 100, total: 100, next_page: nil } }

    response = described_class.ok(->(shown) { "ids #{shown[:data].first[:id]}..#{shown[:data].last[:id]}" }, payload, list_key: :data)

    summary, json = texts(response)
    shown = JSON.parse(json)["data"]
    expect(shown.size).to be < 100
    expect(summary).to eq("ids 0..#{shown.size - 1} showing #{shown.size} of 100; page cut to fit, pass a smaller per_page")
    expect(response.structured_content[:data].size).to eq(shown.size)
  end

  it "cuts a list without paging and names it" do
    payload = { id: 7, failures: Array.new(200) { |i| { test_case_id: i, message: "x" * 1_000 } } }

    summary, json = texts(described_class.ok("Build #7", payload, list_key: :failures))

    expect(summary.length + json.length).to be <= 50_000
    expect(summary).to eq("Build #7 showing #{JSON.parse(json)['failures'].size} of 200 failures")
  end

  it "leaves a payload that fits untouched and caps the summary at 2,000 characters" do
    summary, json = texts(described_class.ok("y" * 5_000, { a: 1 }, list_key: nil))
    expect(summary.length).to eq(2_000)
    expect(json).to eq('{"a":1}')
  end

  it "marks an error" do
    response = described_class.error("No project 'x'.")
    expect(response.error?).to be(true)
    expect(texts(response)).to eq([ "No project 'x'." ])
  end
end
