require "rails_helper"

RSpec.describe "Phone layout", type: :system do
  let(:user) { create(:user) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  [ 360, 430 ].each do |width|
    it "nav fits a phone at #{width}px" do
      sign_in_as(user)

      at_phone_width(width) do
        visit root_path
        expect(page.evaluate_script("window.innerWidth")).to eq(width)
        expect_no_horizontal_scroll
        find("#account-menu summary").click
        expect_tap_targets("#account-menu summary, #account-menu a, #account-menu button")
        expect_no_horizontal_scroll
        click_on "Sign out"
        expect(page).to have_current_path(new_session_path)
      end
    end
  end

  describe "project list, project health and builds list" do
    let(:project) { create(:project, owner: user, name: "Phone project") }
    let(:long_branch) { "feature/a-very-long-branch-name-that-would-overflow-a-phone" }
    let(:long_message) { "Refactor the extremely verbose reporting pipeline so that every adapter shares one retry policy and stops overflowing" }

    before do
      30.times do |i|
        create(:build, project: project, branch: long_branch, commit_sha: "abc#{i}f1234",
                       commit_message: long_message, passed_count: 9, total_count: 10,
                       status: (i == 3 ? "failed" : "passed"), failed_count: (i == 3 ? 1 : 0),
                       duration_ms: 125_000)
      end
      sign_in_as(user)
    end

    [ 360, 430 ].each do |width|
      it "fit a phone at #{width}px" do
        at_phone_width(width) do
          [ projects_path, project_path(project), project_builds_path(project), project_builds_path(project, page: 2) ].each do |path|
            visit path
            expect(page).to have_css("main")
            expect_no_horizontal_scroll
            expect_tap_targets("main a, main button, main select, main summary")
          end

          visit project_path(project)
          tile_lefts = page.evaluate_script(
            "Array.from(document.querySelectorAll('[data-testid=stat-tiles] > div')).map(function (el) { return el.getBoundingClientRect().left })"
          )
          expect(tile_lefts.size).to eq(4)
          expect(tile_lefts.uniq.size).to eq(1)

          visit project_builds_path(project)
          row_widths = page.evaluate_script(
            "Array.from(document.querySelectorAll('#builds > div')).map(function (el) { return el.getBoundingClientRect().width })"
          )
          expect(row_widths).not_to be_empty
          expect(row_widths.max).to be <= width
        end
      end
    end
  end

  describe "build page and failed-test card" do
    let(:project) { create(:project, owner: user, name: "Phone project") }
    let(:build) do
      create(:build, project: project, ci_run_key: "ci-1", latest_attempt: 3, status: "failed", total_count: 30, failed_count: 2,
                     passed_count: 28, branch: "feature/a-very-long-branch-name-that-would-overflow-a-phone",
                     commit_message: "Refactor the extremely verbose reporting pipeline so that every adapter shares one retry policy")
    end
    let(:runs) do
      shards = (1..4).map { |i| create(:run, project: project, build: build, attempt: 1, shard_label: "shard-with-a-long-label-#{i}", shard_index: i, shard_total: 4) }
      shards + [ 2, 3 ].map { |n| create(:run, project: project, build: build, attempt: n, shard_label: "shard-with-a-long-label-1", shard_index: 1, shard_total: 4) }
    end
    let(:message) { ("timeout waiting for selector " * 60) + "https://example.test/#{'a' * 300}" }
    let(:backtrace) { (1..120).map { |i| "/gems/some-gem-1.0/lib/some/deeply/nested/path/file_#{i}.rb:#{i}:in 'method_#{i}'" }.join("\n") }
    let!(:failed) do
      create(:test_result, run: runs.first, status: "failed", exception_class: "Selenium::WebDriver::Error::TimeoutError",
                           failure_message: message, backtrace: backtrace, app_frame: "spec/checkout_spec.rb:12:in 'x'",
                           error_group: create(:error_group, project: project)).tap do |result|
        result.attachments.attach(io: StringIO.new(png(1200, 600)), filename: "shot.png", content_type: "image/png", metadata: { "name" => "screenshot" })
        result.attachments.attach(io: StringIO.new("x"), filename: "run.mp4", content_type: "video/mp4", metadata: { "name" => "video" })
      end
    end
    let!(:also_failed) do
      create(:test_result, run: runs.second, status: "failed", exception_class: "Selenium::WebDriver::Error::TimeoutError",
                           failure_message: "short", error_group: failed.error_group)
    end

    def png(width, height)
      chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
      rows = (("\0" + ("\x88\x88\x88" * width)) * height)
      "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
        chunk.call("IDAT", Zlib::Deflate.deflate(rows)) + chunk.call("IEND", "")
    end

    before { sign_in_as(user) }

    [ 360, 430 ].each do |width|
      it "build page and failed card fit a phone at #{width}px" do
        at_phone_width(width) do
          visit project_build_path(project, build)
          expect(page).to have_css("#test_result_#{failed.id}[open]")
          expect_no_horizontal_scroll
          expect_tap_targets("main a, main button, main select, main summary")

          positions = page.evaluate_script(<<~JS)
            (function () {
              var card = document.getElementById("test_result_#{failed.id}");
              var top = function (el) { return el.getBoundingClientRect().top };
              return {
                message: top(card.querySelector("pre")),
                shot: top(card.querySelector("img")),
                backtrace: top(card.querySelector("[data-testid=stack-trace]")),
                backtraceOpen: card.querySelector("[data-testid=stack-trace]").open
              };
            })()
          JS
          expect(positions["backtraceOpen"]).to eq(false)
          expect(positions["message"]).to be < positions["shot"]
          expect(positions["shot"]).to be < positions["backtrace"]
          expect(page).to have_css("#test_result_#{failed.id} [data-testid=stack-trace] > summary", text: "Backtrace")

          find("#test_result_#{failed.id} [data-testid=stack-trace] > summary").click
          expect(page).to have_css("#test_result_#{failed.id} [data-testid=stack-trace][open]")
          expect_no_horizontal_scroll
          expect_tap_targets("#test_result_#{failed.id} summary")
        end
      end
    end

    it "opens and scrolls to the card named by ?result=" do
      target_case = create(:test_case, project: project, full_name: "Zebra last", file_path: "spec/z_spec.rb")
      25.times { |i| create(:test_result, run: runs.first, status: "passed", test_case: create(:test_case, project: project, file_path: "spec/a#{i}_spec.rb")) }
      target = create(:test_result, run: runs.first, status: "passed", test_case: target_case)
      other = create(:test_result, run: create(:run, project: create(:project, owner: user)), status: "passed")

      at_phone_width(360) do
        visit project_build_path(project, build, result: other.id)
        expect(page).to have_css("#test_result_#{failed.id}[open]")
        expect(page).not_to have_css("#test_result_#{other.id}")
        expect(page.evaluate_script("window.scrollY")).to eq(0)

        visit project_build_path(project, build, result: target.id)
        expect(page).to have_css("#test_result_#{target.id}[open]")
        top = nil
        20.times do
          top = page.evaluate_script("document.getElementById('test_result_#{target.id}').getBoundingClientRect().top")
          break if top >= 0 && top < 800
          sleep 0.1
        end
        expect(top).to be_between(0, 800)
      end
    end
  end

  it "keeps Tokens reachable in the account menu at desktop width" do
    sign_in_as(user)
    find("#account-menu summary").click
    within("#account-menu") { click_on "Tokens" }
    expect(page).to have_current_path(personal_tokens_path)
  end
end
