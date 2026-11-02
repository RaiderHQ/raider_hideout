require "rails_helper"

RSpec.describe "Screenshot comparison", type: :system do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:build) { create(:build, project: project, status: "failed", ci_run_key: "ci-1", latest_attempt: 1) }
  let(:run) { create(:run, project: project, build: build, attempt: 1) }
  let(:dir) { Rails.root.join("spec/fixtures/files/payloads/comparisons/attachments") }
  let(:entry) do
    { "name" => "home", "status" => "failed", "baseline" => "b/home.png", "diff_pixels" => 1_797_705, "diff_ratio" => 0.9992579375667022,
      "threshold" => 0.2, "max_diff_pixels" => 0, "max_diff_ratio" => nil, "expected_size" => [ 1920, 937 ], "actual_size" => [ 1920, 937 ] }
  end

  before do
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  def attach(result, name, file)
    result.attachments.attach(io: File.open(dir.join(file)), filename: file, content_type: "image/png", metadata: { "name" => name })
  end

  def failed_result(status: "failed", comparisons: [ entry ], kinds: %w[expected actual diff], screenshot: true)
    create(:test_result, run: run, status: status, comparisons: comparisons).tap do |r|
      files = { "expected" => "0-expected.png", "actual" => "1-actual.png", "diff" => "2-diff.png" }
      kinds.each { |k| attach(r, "comparison:home:#{k}", files[k]) }
      attach(r, "screenshot", "3-screenshot.png") if screenshot
    end
  end

  def card(result) = "#" + ActionView::RecordIdentifier.dom_id(result)
  def section(result) = "#{card(result)} [data-testid=screenshot-comparison]"
  def visit_build = visit(project_build_path(project, build))

  it "shows numbers, three tabs, the diff by default, and switches tabs" do
    result = failed_result
    visit_build
    within(section(result)) do
      expect(page).to have_text("Screenshot comparison")
      expect(page).to have_text("home")
      expect(page).to have_text("1,797,705 pixels (99.93%) differ")
      expect(page).to have_text("Allowed: 0 pixels, threshold 0.2")
      expect(page).to have_css("[role=tab]", count: 3)
      expect(page).to have_css("img[alt='Diff screenshot for home']", visible: :visible)
      expect(page).to have_css("img[alt='Expected screenshot for home']", visible: :hidden)
      click_on "Expected"
      expect(page).to have_css("[role=tab][aria-selected=true]", text: "Expected")
      expect(page).to have_css("[role=tab][aria-selected=false]", text: "Diff")
      expect(page).to have_css("img[alt='Expected screenshot for home']", visible: :visible)
      expect(page).to have_css("img[alt='Diff screenshot for home']", visible: :hidden)
    end
  end

  it "keeps comparison images out of the main slot and others list" do
    result = failed_result
    visit_build
    shot = result.attachments.find { |a| result.attachment_name(a) == "screenshot" }
    outside = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#{card(result)} img")).filter(function (i) { return !i.closest("[data-testid=screenshot-comparison]") }).map(function (i) { return i.getAttribute("src") })
    JS
    expect(outside.size).to eq(1)
    expect(outside.first).to eq("/attachments/#{shot.id}")
  end

  it "shows the section on a quarantined result" do
    result = failed_result(status: "quarantined")
    visit_build
    expect(page).to have_css(section(result), visible: :all)
  end

  it "shows no comparison image on a passed result (H3)" do
    result = create(:test_result, run: run, status: "passed")
    attach(result, "comparison:home:actual", "1-actual.png")
    visit project_build_path(project, build)
    expect(page).not_to have_css("#{card(result)} img", visible: :all)
    expect(page).not_to have_css("[data-testid=screenshot-comparison]", visible: :all)
  end

  it "shows numbers without tabs when attachments were purged" do
    result = failed_result(kinds: [], screenshot: false)
    run.update!(attachments_purged_at: Time.current)
    visit_build
    expect(page).to have_css("#{card(result)} [data-testid=attachments-expired]")
    within(section(result)) do
      expect(page).to have_text("1,797,705 pixels (99.93%) differ")
      expect(page).not_to have_css("[role=tablist]")
    end
  end

  it "selects Actual when only actual is present" do
    result = failed_result(kinds: %w[actual])
    visit_build
    within(section(result)) do
      expect(page).to have_css("[role=tab]", count: 1)
      expect(page).to have_css("[role=tab][aria-selected=true]", text: "Actual")
    end
  end

  it "renders blocks for images with no record (H2)" do
    result = failed_result(comparisons: nil, kinds: %w[expected diff])
    visit_build
    within(section(result)) do
      expect(page).to have_text("home")
      expect(page).to have_css("[role=tab]", count: 2)
      expect(page).not_to have_text("differ")
    end
  end

  it "renders baseline and a record-less name as literal text" do
    result = failed_result(comparisons: [ entry.merge("baseline" => "<b>x</b>.png") ])
    attach(result, "comparison:a-b_c/d:actual", "1-actual.png")
    visit_build
    within(section(result)) do
      expect(page).to have_text("Baseline: <b>x</b>.png")
      expect(page).to have_no_css("b")
      expect(page).to have_css("p", text: "a-b_c/d")
    end
  end

  it "navigates tabs with the arrow keys and labels the tablist" do
    result = failed_result
    visit_build
    within(section(result)) do
      expect(page).to have_css("[role=tablist][aria-label='Screenshots for home']")
      expect(page).to have_css("[role=tabpanel]", count: 3, visible: :all)
      find("[role=tab][aria-selected=true]", text: "Diff").send_keys(:right)
      expect(page).to have_css("[role=tab][aria-selected=true]", text: "Expected")
      tab = find("[role=tab][aria-selected=true]")
      expect(page).to have_css("##{tab['aria-controls']}", visible: :visible)
    end
  end

  it "wraps a long baseline-created name on a phone" do
    long = "a" * 100
    result = failed_result(kinds: %w[actual], comparisons: [ entry.merge("name" => long, "status" => "created") ])
    attach(result, "comparison:#{long}:actual", "1-actual.png")
    at_phone_width(360) do
      visit_build
      expect(page).to have_css("#{section(result)} p", text: long)
      expect_no_horizontal_scroll
    end
  end

  it "shows baseline created with an Actual link, and matched count" do
    result = failed_result(kinds: %w[actual], comparisons: [ entry.merge("status" => "created"), entry.merge("name" => "a", "status" => "passed"), entry.merge("name" => "b", "status" => "passed") ])
    visit_build
    within(section(result)) do
      expect(page).to have_text("Baseline created")
      expect(page).to have_link("Actual")
      expect(page).to have_text("2 matched")
    end
  end

  it "fits a phone at 360px" do
    result = failed_result
    at_phone_width(360) do
      visit_build
      expect(page).to have_css(section(result))
      expect_no_horizontal_scroll
      expect_tap_targets("[data-testid=screenshot-comparison] [role=tab]")
    end
  end
end
