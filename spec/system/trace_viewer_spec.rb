require "rails_helper"
require "json"

RSpec.describe "Trace viewer panels", type: :system do
  let(:member) { create(:user) }
  let(:project) { create(:project, organization: member.organizations.first) }
  let(:result) { create(:test_result, run: create(:run, project: project)) }
  let(:data) { JSON.parse(file_fixture("trace-v1.json").read) }

  def open_trace(bytes)
    trace = attach_trace(result, io: StringIO.new(bytes))
    visit new_session_path
    fill_in "Email", with: member.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
    visit test_result_trace_path(result, trace)
  end

  def open_json(json)
    open_trace(RawZip.build([ { name: "trace.json", data: JSON.generate(json), method: :stored } ]))
  end

  def select_step(text)
    find("#trace-timeline [data-testid=trace-step]", text: text, match: :first).click
  end

  it "marks the failed group and selects it by default" do
    failed = data["steps"].count { |s| s["status"] == "failed" }
    open_trace(file_fixture("trace-v1.zip").binread)
    expect(page).to have_css("[data-testid=trace-step-failed]", count: failed)
    expect(page).to have_css("[aria-current=true]", text: "eventually")
  end

  it "nests child steps inside collapsible groups" do
    open_trace(file_fixture("trace-v1.zip").binread)
    expect(page).to have_css("#trace-timeline details[open] ul [data-testid=trace-step]", text: "text")
  end

  it "hides the value of a password step" do
    open_trace(file_fixture("trace-v1.zip").binread)
    all("#trace-timeline [data-testid=trace-step]", minimum: 3)[1].click
    expect(page).to have_css("#trace-detail", text: "Hidden (password field)")
    expect(page).to have_css("[data-testid=trace-screenshot]")
    expect(page).to have_css("[data-testid=trace-rect]", visible: :all)
    expect(page).to have_text("element before the action")
  end

  it "shows network rows for the step, and every row with Show all" do
    steps = data["network"].count { |n| n["step_index"] == 6 }
    open_trace(file_fixture("trace-v1.zip").binread)
    select_step("click")
    expect(page).to have_css("[data-testid=trace-network-row]", count: steps)
    expect(page).to have_css("[data-testid=trace-network-row]", text: "/api")
    check "Show all"
    expect(page).to have_css("[data-testid=trace-network-row]", count: data["network"].size)
  end

  it "shows the console error text" do
    open_trace(file_fixture("trace-v1.zip").binread)
    select_step("click")
    click_on "Console"
    expect(page).to have_css("[data-testid=trace-console-row]", text: data["console"].first["text"])
  end

  it "says Not captured and fetches nothing for a traversal path" do
    data["steps"][0]["screenshot"] = "../x"
    data["steps"][0]["snapshot"] = nil
    open_json(data)
    select_step("navigate")
    expect(page).to have_css("#trace-detail", text: "Not captured")
    expect(page).to have_no_css("[data-testid=trace-screenshot]")
  end

  it "says so when network capture is unavailable" do
    data["capabilities"]["network"] = false
    open_json(data)
    expect(page).to have_css("#trace-network", text: "Not available in this browser")
  end

  it "adds a notice for truncated screenshots only" do
    data["truncated"]["screenshots"] = 3
    open_json(data)
    expect(page).to have_css("#trace-notices [data-testid=trace-notice]", count: 1, text: "Older screenshots removed to keep the trace small")
  end

  it "shows an empty tab message when the step has no rows" do
    open_json(data.merge("network" => []))
    expect(page).to have_css("#trace-network", text: "Nothing during this step")
  end

  it "renders hostile error text as text" do
    data["steps"][0]["error"] = { "class" => "X", "message" => "<img src=x onerror=window.__pwned=3>" }
    data["console"] = [ { "step_index" => 1, "level" => "error", "text" => "<img src=x onerror=window.__pwned=5>" } ]
    open_json(data)
    select_step("navigate")
    expect(page).to have_css("#trace-detail", text: "<img src=x onerror=window.__pwned=3>")
    expect(page).to have_no_css("#trace-detail img[src=x]")
    click_on "Console"
    expect(page).to have_css("[data-testid=trace-console-row]", text: "<img src=x onerror=window.__pwned=5>")
    expect(page).to have_no_css("#trace-console img")
    expect(page.evaluate_script("window.__pwned")).to be_nil
  end

  it "keeps other steps usable when a screenshot cannot be read" do
    data["steps"][0]["screenshot"] = "steps/0001.jpg"
    bytes = RawZip.build([ { name: "trace.json", data: JSON.generate(data), method: :stored },
                          { name: "steps/0001.jpg", data: "\0" * (2 * 1024 * 1024), method: :deflate, declared_size: 1024 } ])
    open_trace(bytes)
    select_step("navigate")
    expect(page).to have_css("#trace-notices [data-testid=trace-error]", text: "This step's file couldn't be read: entry larger than declared")
    expect(page).not_to have_text("This trace can't be opened")
    select_step("click")
    expect(page).to have_css("#trace-network [data-testid=trace-network-row]", text: "/api")
  end

  it "ignores null items in steps, network and console" do
    open_json(data.merge("steps" => [ nil, data["steps"][0] ], "network" => [ nil ], "console" => [ nil ]))
    expect(page).to have_css("[data-testid=trace-step]", count: 1)
    click_on "Console"
    expect(page).to have_css("#trace-console", text: "Nothing during this step")
  end

  it "does not overflow horizontally at phone width" do
    cdp = page.driver.browser
    begin
      cdp.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 800, deviceScaleFactor: 1, mobile: false)
      open_trace(file_fixture("trace-v1.zip").binread)
      expect(page).to have_css("[data-testid=trace-step]", minimum: 1)
      expect(page.evaluate_script("document.documentElement.clientWidth")).to be <= 375
      root = "document.querySelector('[data-controller=trace-viewer]')"
      expect(page.evaluate_script("#{root}.scrollWidth <= #{root}.clientWidth")).to be(true)
      expect(page.evaluate_script("#{root}.getBoundingClientRect().right <= document.documentElement.clientWidth")).to be(true)
      %w[#trace-timeline #trace-detail #trace-network #trace-console].each do |id|
        expect(page.evaluate_script("(e => e.scrollWidth <= e.clientWidth)(document.querySelector('#{id}'))")).to be(true), "#{id} overflows"
      end
    ensure
      cdp.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end
end
