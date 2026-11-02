require "rails_helper"
require "json"

RSpec.describe "Trace viewer zip safety", type: :system do
  let(:member) { create(:user) }
  let(:project) { create(:project, organization: member.organizations.first) }
  let(:result) { create(:test_result, run: create(:run, project: project)) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  def open_trace(bytes)
    trace = attach_trace(result, io: StringIO.new(bytes))
    sign_in_as(member)
    visit test_result_trace_path(result, trace)
  end

  def index_json(extra = {})
    JSON.generate({ format: "raider-trace", version: 1, steps: [] }.merge(extra))
  end

  def entry(name, data = "x", **opts) = { name: name, data: data, method: :stored }.merge(opts)

  def trace_json_of(bytes)
    Dir.mktmpdir do |dir|
      File.binwrite("#{dir}/t.zip", bytes)
      IO.popen(["unzip", "-p", "#{dir}/t.zip", "trace.json"], &:read)
    end
  end

  def expect_refused
    expect(page).to have_css("[data-testid=trace-error]", text: /\AThis trace can't be opened/)
  end

  it "opens the fixture with one step per trace.json step" do
    bytes = file_fixture("trace-v1.zip").binread
    steps = JSON.parse(trace_json_of(bytes))["steps"].size
    open_trace(bytes)
    expect(page).to have_css("#trace-timeline [data-testid=trace-step]", count: steps)
  end

  {
    "a path traversal name" => ["entry name not allowed", ->(s) { [s.entry("trace.json", s.index_json), s.entry("../evil.html")] }],
    "a disallowed extension" => ["entry name not allowed", ->(s) { [s.entry("trace.json", s.index_json), s.entry("steps/0001.exe")] }],
    "a symlink entry" => ["symlink entry", ->(s) { [s.entry("trace.json", s.index_json), s.entry("steps/0001.html", "x", unix_mode: 0o120777)] }],
    "too many entries" => ["too many entries", ->(s) { [s.entry("trace.json", s.index_json)] + (1..401).map { |i| s.entry(format("steps/%04d.html", i)) } }],
    "the encryption flag" => ["encrypted entry", ->(s) { [s.entry("trace.json", s.index_json), s.entry("steps/0001.html", "x", flags: 1)] }],
    "an unsupported method" => ["unsupported compression", ->(s) { [s.entry("trace.json", s.index_json), s.entry("steps/0001.html", "x", method: 12)] }],
    "a lying bomb" => ["entry larger than declared", ->(s) { [s.entry("trace.json", "\0" * (2 * 1024 * 1024), method: :deflate, declared_size: 1024)] }]
  }.each do |label, (reason, build)|
    it "refuses #{label}" do
      open_trace(RawZip.build(build.call(self)))
      expect_refused
      expect(page).to have_css("[data-testid=trace-error]", text: "This trace can't be opened: #{reason}")
    end
  end

  it "says so when the file is not a Raider trace" do
    open_trace(RawZip.build([entry("trace.json", '{"format":"other"}')]))
    expect(page).to have_css("[data-testid=trace-error]", text: "This file is not a Raider trace.")
  end

  it "asks to update Hideout for a newer version" do
    open_trace(RawZip.build([entry("trace.json", index_json(version: 2))]))
    expect(page).to have_css("[data-testid=trace-error]", text: "This trace was made by a newer Raider. Update Hideout to open it.")
  end
end
