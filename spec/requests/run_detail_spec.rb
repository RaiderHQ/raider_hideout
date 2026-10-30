require "rails_helper"

RSpec.describe "Run detail", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }

  before { sign_in(user) }

  it "groups results by file and shows failure details and attachments" do
    data = build_payload(results: [
      build_result("file_path" => "spec/cart_spec.rb", "full_name" => "Cart adds", "identifier" => "./spec/cart_spec.rb[1:1]"),
      build_result("file_path" => "spec/login_spec.rb", "full_name" => "Login fails", "status" => "failed",
                   "identifier" => "./spec/login_spec.rb[1:2]",
                   "failure" => { "message" => "expected true", "exception_class" => "RSpec::Expectations::ExpectationNotMetError",
                                  "backtrace" => [ "spec/login_spec.rb:14" ] },
                   "attachments" => [ { "name" => "screenshot", "part" => "att_0", "content_type" => "image/png" },
                                     { "name" => "video", "part" => "att_1", "content_type" => "video/mp4" } ])
    ])
    run = Ingest.call(project: project, payload: data.to_json,
                      files: { "att_0" => upload_file, "att_1" => upload_file("run.mp4", "MP4", "video/mp4") }).run

    get project_run_path(project, run)

    body = response.body
    expect(body).to include("spec/cart_spec.rb", "spec/login_spec.rb", "Cart adds", "Login fails")
    expect(body).to include("expected true", "RSpec::Expectations::ExpectationNotMetError", "spec/login_spec.rb:14")
    expect(body).to include("<img").and include("<video")
    expect(body.index("spec/login_spec.rb")).to be < body.index("spec/cart_spec.rb")
  end

  it "keeps Turbo off download links so the redirect to R2 is a plain navigation" do
    data = build_payload(results: [
      build_result("attachments" => [ { "name" => "trace", "part" => "att_0", "content_type" => "application/zip" } ])
    ])
    run = Ingest.call(project: project, payload: data.to_json,
                      files: { "att_0" => upload_file("trace.zip", "PK", "application/zip") }).run

    get project_run_path(project, run)

    link = Nokogiri::HTML(response.body).at_css("a[href*='disposition=attachment']")
    expect(link["data-turbo"]).to eq("false")
    expect(link["data-turbo-prefetch"]).to eq("false")
  end

  it "links back to its build and shows its shard label" do
    run = create(:run, project: project, shard_label: "rspec#3")
    get project_run_path(project, run)
    expect(response.body).to include(%(href="#{project_build_path(project, run.build)}">Build ##{run.build.id}</a>))
    expect(response.body).to include("rspec#3")
  end

  it "orders cards in a file deterministically: failed first, then name" do
    run = create(:run, project: project)
    %w[Zeta Alpha].each do |name|
      create(:test_result, run: run, test_case: create(:test_case, project: project, file_path: "spec/a_spec.rb", full_name: name))
    end
    create(:test_result, run: run, status: "failed",
                         test_case: create(:test_case, project: project, file_path: "spec/a_spec.rb", full_name: "Omega"))
    get project_run_path(project, run)
    positions = %w[Omega Alpha Zeta].map { |name| response.body.index(">#{name}<") }
    expect(positions).to eq(positions.sort)
  end

  it "404s for a run in another project" do
    other_run = create(:run)
    get project_run_path(project, other_run)
    expect(response).to have_http_status(:not_found)
  end

  it "does not render a non-http build URL as a link" do
    run = create(:run, project: project, build_url: "javascript:alert(1)")
    get project_run_path(project, run)
    expect(response.body).not_to include("javascript:")
  end

  it "escapes hostile strings" do
    data = build_payload(results: [ build_result("full_name" => "<script>alert(1)</script>", "status" => "failed",
                                                "failure" => { "message" => "<script>alert(1)</script>" }) ])
    run = Ingest.call(project: project, payload: data.to_json, files: {}).run
    get project_run_path(project, run)
    expect(response.body).to include("&lt;script&gt;")
    expect(response.body).not_to include("<script>alert(1)")
  end

  it "404s for another user's project slug on run and test case pages" do
    other = create(:project)
    run = create(:run, project: other)
    result = create(:test_result, run: run)
    get project_run_path(other, run)
    expect(response).to have_http_status(:not_found)
    get project_test_case_path(other, result.test_case)
    expect(response).to have_http_status(:not_found)
  end

  describe "failure card" do
    let(:run) { create(:run, project: project, environment: { "browser" => "chrome" }) }

    def failing(attrs = {}, attachments: [])
      result = create(:test_result, **{ run: run, status: "failed", exception_class: "RuntimeError", failure_message: "kaboom" }.merge(attrs))
      attachments.each do |name, type|
        result.attachments.attach(io: StringIO.new("x"), filename: name, content_type: type, metadata: { "name" => name })
      end
      result
    end

    def page
      get project_run_path(project, run)
      Nokogiri::HTML(response.body)
    end

    it "shows the location, browser and screenshot for a failure with an app_frame" do
      failing({ app_frame: "spec/a_spec.rb:12:in 'x'", backtrace: "spec/a_spec.rb:12:in 'x'\n/gems/r.rb:3" },
              attachments: [ [ "screenshot", "image/png" ] ])
      doc = page
      location = doc.at_css("[data-testid=failure-location]")
      expect(location.text).to include("spec/a_spec.rb:12", "chrome")
      expect(location["title"]).to eq("spec/a_spec.rb:12:in 'x'")
      expect(doc.at_css("details img")).to be_present
      expect(doc.css("[data-testid=stack-frame-project]").size).to eq(1)
    end

    it "shows the message without an img when there are no attachments" do
      failing
      doc = page
      expect(doc.at_css("details pre").text).to include("kaboom")
      expect(doc.at_css("details img")).to be_nil
    end

    it "shows the expired note and no img when attachments expired" do
      run.update!(attachments_purged_at: 1.day.ago)
      failing
      doc = page
      expect(doc.at_css("details pre").text).to include("kaboom")
      expect(doc.at_css("[data-testid=attachments-expired]")).to be_present
      expect(doc.at_css("details img")).to be_nil
    end

    it "renders no location or trace without app_frame and backtrace" do
      failing
      doc = page
      expect(doc.at_css("[data-testid=failure-location]")).to be_nil
      expect(doc.at_css("[data-testid=stack-trace]")).to be_nil
    end

    it "folds an all-gem backtrace into one toggle with its count" do
      failing({ backtrace: (1..7).map { "/gems/x/lib/y.rb:#{_1}:in 'z'" }.join("\n") })
      folded = page.css("[data-testid=stack-frames-folded]")
      expect(folded.size).to eq(1)
      expect(folded.first.at_css("summary").text).to include("7 more")
    end

    it "omits the browser when the run has none" do
      run.update!(environment: {})
      failing({ app_frame: "spec/a_spec.rb:12" })
      expect(page.at_css("[data-testid=failure-location]").text).not_to include("chrome")
    end

    it "wraps a video in a Failure video fold" do
      failing(attachments: [ [ "video", "video/mp4" ] ])
      expect(page.at_css("details video")).to be_present
      expect(response.body).to include("Failure video")
    end

    it "puts the attachment named screenshot in the slot even when another image comes first" do
      failing(attachments: [ [ "earlier", "image/png" ], [ "screenshot", "image/png" ] ])
      expect(page.css("details img").map { _1["alt"] }.first).to eq("screenshot")
    end

    it "falls back to the first image when none is named screenshot" do
      failing(attachments: [ [ "first", "image/png" ], [ "second", "image/png" ] ])
      expect(page.css("details img").map { _1["alt"] }.first).to eq("first")
    end

    it "renders without the browser when the run environment is not a Hash" do
      run.update_column(:environment, [ "chrome" ])
      failing({ app_frame: "spec/a_spec.rb:12" })
      get project_run_path(project, run)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("[data-testid=failure-location]").text).not_to include("chrome")
    end

    it "escapes script tags in the message and backtrace" do
      xss = "<script>alert(1)</script>"
      failing({ failure_message: xss, backtrace: "spec/a_spec.rb:1:in '#{xss}'" })
      doc = page
      expect(doc.at_css("[data-testid=stack-trace]")).to be_present
      expect(doc.css("script").map(&:text)).not_to include("alert(1)")
      expect(response.body).not_to include(xss)
      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    end

    it "renders no failure-location for a passed result" do
      create(:test_result, run: run, status: "passed", app_frame: "spec/a_spec.rb:12")
      expect(page.at_css("[data-testid=failure-location]")).to be_nil
    end
  end
end
