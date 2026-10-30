require "rails_helper"

RSpec.describe Ingest do
  include ActiveJob::TestHelper

  let(:project) { create(:project) }

  def ingest(data, files = {})
    described_class.call(project: project, payload: data.to_json, files: files)
  end

  it "creates a run with counts, git and CI metadata" do
    data = build_payload(results: [
      build_result,
      build_result("identifier" => "./spec/login_spec.rb[1:2]", "full_name" => "Login fails", "status" => "failed",
                   "failure" => { "message" => "boom", "exception_class" => "RuntimeError", "backtrace" => [ "a.rb:1", "b.rb:2" ] }),
      build_result("identifier" => "./spec/login_spec.rb[1:3]", "full_name" => "Login later", "status" => "skipped")
    ])
    result = ingest(data)
    run = result.run
    expect(result.created).to be(true)
    expect(run).to have_attributes(status: "failed", total_count: 3, passed_count: 1, failed_count: 1, skipped_count: 1,
                                   branch: "main", commit_sha: "abc", ci_provider: "github_actions", duration_ms: 5000)
    failed = run.test_results.find_by(status: "failed")
    expect(failed).to have_attributes(failure_message: "boom", exception_class: "RuntimeError", backtrace: "a.rb:1\nb.rb:2")
  end

  it "replaces NUL bytes in strings and keys so every adapter can store them" do
    data = build_payload(results: [
      build_result("full_name" => "Login \u0000works", "status" => "failed",
                   "failure" => { "message" => "bo\u0000om", "exception_class" => "RuntimeError", "backtrace" => [ "a.rb:1\u0000" ] })
    ])
    data["run"]["environment"] = { "k\u0000ey" => "v" }
    run = ingest(data).run
    result = run.test_results.sole
    expect(result.test_case.full_name).to eq("Login \u{FFFD}works")
    expect(result).to have_attributes(failure_message: "bo\u{FFFD}om", backtrace: "a.rb:1\u{FFFD}")
    expect(run.reload.environment).to eq("k\u{FFFD}ey" => "v")
    expect([ result.test_case.full_name, result.failure_message, result.backtrace ].join).not_to include("\u0000")
  end

  it "reuses test cases across runs and updates their last status" do
    ingest(build_payload)
    ingest(build_payload(results: [ build_result("status" => "failed") ]))
    expect(project.test_cases.count).to eq(1)
    expect(project.test_cases.first).to have_attributes(last_status: "failed", full_name: "Login works")
  end

  it "is idempotent on client_run_id" do
    data = build_payload
    first = ingest(data)
    second = ingest(data)
    expect(second.created).to be(false)
    expect(second.run).to eq(first.run)
    expect(project.runs.count).to eq(1)
  end

  it "marks retry passes and enqueues flaky analysis" do
    expect { ingest(build_payload(results: [ build_result("attempts" => 2) ])) }.to have_enqueued_job(FlakinessJob)
    expect(TestResult.last.retried_flaky).to be(true)
  end

  it "stores attachments with their names" do
    data = build_payload(results: [ build_result("status" => "failed",
      "attachments" => [ { "name" => "screenshot", "part" => "att_0", "content_type" => "image/png" } ]) ])
    run = ingest(data, { "att_0" => upload_file }).run
    result = run.test_results.first
    expect(result.attachments.count).to eq(1)
    expect(result.attachment_name(result.attachments.first)).to eq("screenshot")
    expect(result.attachments.first.download).to eq("PNG")
  end

  it "accepts non-string attachment names and environment values" do
    data = build_payload(results: [ build_result("attachments" => [ { "name" => 7, "part" => "att_0", "content_type" => "image/png" } ]) ])
    data["run"]["environment"] = { "ruby" => "4.0.2", "headless" => true }
    run = ingest(data, { "att_0" => upload_file("my shot (1).png") }).run
    expect(run.environment).to eq({ "ruby" => "4.0.2", "headless" => true })
    result = run.test_results.first
    expect(result.attachment_name(result.attachments.first)).to eq("7")
  end

  it "ingests a run without ci, git or environment" do
    data = build_payload
    data["run"] = { "started_at" => "2026-10-10T12:00:00Z" }
    run = ingest(data).run
    expect(run).to have_attributes(branch: nil, commit_sha: nil, ci_provider: nil, environment: {}, duration_ms: nil)
  end

  it "keeps only http(s) build URLs" do
    build = ->(url) { build_payload.tap { |d| d["run"]["ci"]["build_url"] = url } }
    expect(ingest(build.call("https://ci.example/1")).run.build_url).to eq("https://ci.example/1")
    expect(ingest(build.call("javascript:alert(1)")).run.build_url).to be_nil
    expect(ingest(build.call("not a url")).run.build_url).to be_nil
  end

  it "links duplicate names in one payload to a single test case" do
    data = build_payload(results: [ build_result, build_result("identifier" => "./spec/login_spec.rb[1:9]") ])
    run = ingest(data).run
    expect(run.test_results.count).to eq(2)
    expect(project.test_cases.count).to eq(1)
  end

  it "raises Invalid with details for bad payloads" do
    expect { ingest(build_payload(schema_version: 9)) }.to raise_error(Ingest::Invalid) { |e|
      expect(e.details).to eq([ "unsupported schema_version 9; supported: 1, 2" ])
    }
    expect { described_class.call(project: project, payload: "{not json", files: {}) }
      .to raise_error(Ingest::Invalid) { |e| expect(e.details.first).to start_with("payload is not valid JSON") }
  end

  it "raises TooLarge for oversized attachments without creating a run" do
    stub_const("Ingest::MAX_ATTACHMENT_BYTES", 2)
    data = build_payload(results: [ build_result("attachments" => [ { "name" => "s", "part" => "att_0", "content_type" => "image/png" } ]) ])
    expect { ingest(data, { "att_0" => upload_file }) }.to raise_error(Ingest::TooLarge)
    expect(project.runs.count).to eq(0)
  end

  it "stores failure fields only for failed results" do
    failure = { "message" => "boom", "exception_class" => "RuntimeError", "backtrace" => [ "a.rb:1" ] }
    run = ingest(build_payload(results: [ build_result("failure" => failure) ])).run
    expect(run.test_results.first).to have_attributes(failure_message: nil, exception_class: nil, backtrace: nil)
  end

  it "enqueues flaky analysis even if attaching fails, and propagates the error" do
    data = build_payload(results: [ build_result("attachments" => [ { "name" => "s", "part" => "att_0", "content_type" => "image/png" } ]) ])
    allow_any_instance_of(ActiveStorage::Attached::Many).to receive(:attach).and_raise(RuntimeError, "storage down")
    expect { ingest(data, { "att_0" => upload_file }) }
      .to raise_error(RuntimeError, "storage down").and have_enqueued_job(FlakinessJob)
  end

  it "stores normalized tags_text for each result" do
    ingest(build_payload(results: [ build_result("tags" => [ "Smoke", "slow test" ]),
                                    build_result("identifier" => "x", "full_name" => "Other", "tags" => []) ]))

    expect(TestResult.order(:id).pluck(:tags_text)).to eq([ "|smoke|slow test|", "" ])
  end

  describe "app_frame storage" do
    def result_with(frame, status: "failed")
      failure = { "message" => "boom", "exception_class" => "RuntimeError", "backtrace" => [ "a.rb:1" ], "app_frame" => frame }
      build_result("status" => status, "failure" => failure)
    end

    it "stores the app_frame of a failed result" do
      run = ingest(build_payload(results: [ result_with("spec/a_spec.rb:12:in 'x'") ])).run
      expect(run.test_results.sole.app_frame).to eq("spec/a_spec.rb:12:in 'x'")
    end

    it "truncates an app_frame to 500 characters" do
      run = ingest(build_payload(results: [ result_with("a" * 600) ])).run
      expect(run.test_results.sole.app_frame).to eq("a" * 500)
    end

    it "stores nil for a passed result, a blank frame or a non-string frame" do
      results = [ result_with("spec/a_spec.rb:1", status: "passed"), result_with(""), result_with({ "x" => 1 }) ]
      results.each_with_index { |r, i| r["identifier"] = "./spec/x_spec.rb[#{i}]"; r["full_name"] = "T#{i}" }
      run = ingest(build_payload(results: results)).run
      expect(run.test_results.pluck(:app_frame)).to eq([ nil, nil, nil ])
    end
  end

  describe "error grouping" do
    include ActiveSupport::Testing::TimeHelpers

    def failed(identifier, message, app_frame: "spec/pages/login_page.rb:42:in 'LoginPage#submit'", klass: "Capybara::ElementNotFound")
      failure = { "message" => message, "exception_class" => klass,
                  "backtrace" => [ "/home/runner/work/x/x/spec/pages/login_page.rb:42:in 'click'" ] }
      failure["app_frame"] = app_frame unless app_frame == :none
      build_result("identifier" => identifier, "full_name" => "Test #{identifier}", "status" => "failed", "failure" => failure)
    end

    def clustered_payload(prefix = "a")
      same = Array.new(20) { |i| failed("#{prefix}-same-#{i}", "Unable to find css \"#btn-#{i}\"") }
      unique = [ failed("#{prefix}-u1", "timeout"), failed("#{prefix}-u2", "boom", klass: "RuntimeError"),
                 failed("#{prefix}-u3", "Unable to find css \"#x\"", app_frame: "spec/pages/home_page.rb:3:in 'open'") ]
      build_payload(results: same + unique + [ build_result("identifier" => "#{prefix}-ok", "full_name" => "ok #{prefix}") ])
    end

    it "groups a run's failures by signature" do
      run = ingest(clustered_payload).run
      expect(project.error_groups.count).to eq(4)
      expect(run.test_results.where(status: "failed").where(error_group_id: nil)).to be_empty
      expect(run.test_results.where(status: "passed").pluck(:error_group_id)).to eq([ nil ])
      same = run.test_results.where("identifier LIKE 'a-same-%'").distinct.pluck(:error_group_id)
      expect(same.size).to eq(1)
      expect(ErrorGroup.find(same.first)).to have_attributes(
        exception_class: "Capybara::ElementNotFound", normalized_message: "Unable to find css \"…\"",
        frame: "spec/pages/login_page.rb:in submit",
        sample_app_frame: "spec/pages/login_page.rb:42:in 'LoginPage#submit'"
      )
    end

    it "reuses a group in a later run, updating last seen and the sample but not first seen" do
      travel_to(Time.zone.parse("2026-10-10 12:00:00")) { ingest(build_payload(results: [ failed("one", "Unable to find css \"#a\"") ])) }
      group = project.error_groups.sole
      later = build_payload(results: [ failed("two", "Unable to find css \"#b\"", app_frame: "spec/pages/login_page.rb:50:in 'LoginPage#submit'") ])
      run = travel_to(Time.zone.parse("2026-10-12 12:00:00")) { ingest(later).run }

      expect(project.error_groups.count).to eq(1)
      expect(run.test_results.sole.error_group_id).to eq(group.id)
      expect(group.reload).to have_attributes(
        first_seen_at: Time.zone.parse("2026-10-10 12:00:00"), last_seen_at: Time.zone.parse("2026-10-12 12:00:00"),
        sample_message: "Unable to find css \"#b\"", sample_app_frame: "spec/pages/login_page.rb:50:in 'LoginPage#submit'"
      )
    end

    it "keeps each app_frame with its own result when identifiers repeat" do
      run = ingest(build_payload(results: [ failed("dup", "boom", app_frame: "spec/a.rb:1:in 'x'"),
                                            failed("dup", "boom", app_frame: "spec/b.rb:1:in 'y'") ])).run
      frames = run.test_results.order(:id).map { |r| r.error_group.frame }
      expect(frames).to eq([ "spec/a.rb:in x", "spec/b.rb:in y" ])
    end

    it "groups payloads from reporters without app_frame by the backtrace" do
      run = ingest(build_payload(results: [ failed("old", "boom", app_frame: :none) ])).run
      group = run.test_results.sole.error_group
      expect(group).to have_attributes(frame: "spec/pages/login_page.rb:in click", sample_app_frame: nil)
    end

    it "ignores a non-string app_frame instead of rejecting the payload" do
      run = ingest(build_payload(results: [ failed("odd", "boom", app_frame: { "x" => 1 }) ])).run
      expect(run.test_results.sole.error_group).to have_attributes(frame: "spec/pages/login_page.rb:in click",
                                                                   sample_app_frame: nil)
    end

    it "groups a failure with no message, class or backtrace" do
      data = build_payload(results: [ build_result("identifier" => "bare", "status" => "failed") ])
      group = ingest(data).run.test_results.sole.error_group
      expect(group).to have_attributes(exception_class: "UnknownError", normalized_message: "", frame: "")
    end

    it "makes one error_groups upsert per distinct digest" do
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(/\AINSERT INTO "error_groups"/i) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { ingest(clustered_payload) }
      expect(statements.size).to eq(4)
    end

    it "keeps the query count independent of the number of failures" do
      count_queries = lambda do |data|
        queries = 0
        callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { ingest(data) }
        queries
      end
      many = build_payload(results: Array.new(100) { |i| failed("m#{i}", "Error #{i % 5} \"#{i}\"", app_frame: "spec/s#{i % 5}.rb:1:in 'x'") })
      few = build_payload(results: Array.new(5) { |i| failed("f#{i}", "Error #{i} \"#{i}\"", app_frame: "spec/f#{i}.rb:1:in 'x'") })
      count_queries.call(few) # warm up
      expect(count_queries.call(many)).to eq(count_queries.call(build_payload(results: few["results"])))
    end
  end

  describe "build grouping" do
    def shard_payload(index, total: 2, key: "github_actions:acme/app:123:1", results: [ build_result ], attempt: "1")
      build_payload(results: results).tap do |d|
        d["run"]["ci"].merge!("attempt" => attempt, "job" => "test", "build_key" => key)
        d["run"]["shard"] = { "index" => index, "total" => total, "label" => "test##{index}" }
      end
    end

    it "groups shards with the same build_key into one build with summed counts" do
      first = ingest(shard_payload(1, results: [ build_result, build_result("identifier" => "a[1]", "full_name" => "A") ])).run
      second = ingest(shard_payload(2, results: [ build_result("identifier" => "b[1]", "full_name" => "B", "status" => "skipped") ])).run
      build = first.build.reload
      expect(second.build).to eq(build)
      expect(project.builds.count).to eq(1)
      expect(build.runs).to contain_exactly(first, second)
      expect(build).to have_attributes(status: "passed", expected_shards: 2, total_count: 3, passed_count: 2,
                                       skipped_count: 1, build_key: "github_actions:acme/app:123:1",
                                       provider: "github_actions", build_id: "1", attempt: "1", ci_url: "https://ci/1",
                                       branch: "main", commit_sha: "abc", commit_message: "Fix")
      expect(second).to have_attributes(shard_index: 2, shard_total: 2, shard_label: "test#2")
    end

    it "is incomplete until every expected shard has arrived" do
      run = ingest(shard_payload(1)).run
      expect(run.build.reload.status).to eq("incomplete")
    end

    it "is failed when any shard failed" do
      ingest(shard_payload(1, results: [ build_result("status" => "failed") ]))
      run = ingest(shard_payload(2)).run
      expect(run.build.reload).to have_attributes(status: "failed", failed_count: 1, passed_count: 1)
      expect(ingest(shard_payload(1, key: "other", results: [ build_result("status" => "failed") ])).run.build.reload.status)
        .to eq("failed")
    end

    it "keeps a re-run attempt in a separate build" do
      first = ingest(shard_payload(1, total: 1)).run
      second = ingest(shard_payload(1, total: 1, key: "github_actions:acme/app:123:2", attempt: "2")).run
      expect(second.build).not_to eq(first.build)
      expect(second.build).to have_attributes(attempt: "2", status: "passed")
    end

    it "gives a payload without build_key or shard its own build" do
      data = build_payload
      run = ingest(data).run
      expect(run.build).to have_attributes(build_key: "run:#{data['client_run_id']}", status: "passed",
                                           expected_shards: nil, total_count: 1)
      expect(run).to have_attributes(shard_index: nil, shard_total: nil, shard_label: nil)
      expect(ingest(build_payload).run.build).not_to eq(run.build)
    end

    it "never expects shards for synthetic builds of local parallel runs" do
      runs = [ 1, 2 ].map do |index|
        data = build_payload.tap { |d| d["run"]["shard"] = { "index" => index, "total" => 2, "label" => "local##{index}" } }
        ingest(data).run
      end
      builds = runs.map { |r| r.build.reload }
      expect(builds.uniq.size).to eq(2)
      builds.each do |build|
        expect(build).to have_attributes(status: "passed", expected_shards: nil)
        expect(build.shard_progress).to be_nil
      end
    end

    describe "Azure pr_url" do
      def azure_shard(index, pr_url: nil, pr_number: 7)
        build_payload.tap do |d|
          d["run"]["ci"].merge!("provider" => "azure_pipelines", "build_key" => "azure_pipelines:dev.azure.com/o/p/r:42:1")
          d["run"]["shard"] = { "index" => index, "total" => 2, "label" => "s#{index}" }
          d["run"]["git"]["pr"] = { "number" => pr_number, "base_branch" => "main", "head_branch" => "f", "head_sha" => "abc" }.merge(pr_url ? { "url" => pr_url } : {})
        end
      end
      let(:url) { "https://dev.azure.com/o/P/_git/r/pullrequest/7" }

      it "stores provider and pr_url and groups shards into one build" do
        a = ingest(azure_shard(1, pr_url: url)).run.build
        b = ingest(azure_shard(2, pr_url: url)).run.build
        expect(b).to eq(a)
        expect(a.reload).to have_attributes(provider: "azure_pipelines", pr_url: url, pr_number: 7)
      end

      it "backfills pr_url from a later shard" do
        build = ingest(azure_shard(1)).run.build
        expect(build.pr_url).to be_nil
        ingest(azure_shard(2, pr_url: url))
        expect(build.reload.pr_url).to eq(url)
      end

      it "drops non-http(s) and non-string pr_url but accepts the payload" do
        expect(ingest(azure_shard(1, pr_url: "javascript:alert(1)")).run.build.pr_url).to be_nil
        d = azure_shard(1)
        d["run"]["git"]["pr"]["url"] = 123
        expect(ingest(d).run.build.pr_url).to be_nil
      end
    end

    it "stores only http(s) CI URLs on the build" do
      data = build_payload.tap { |d| d["run"]["ci"]["build_url"] = "javascript:alert(1)" }
      expect(ingest(data).run.build.ci_url).to be_nil
    end

    it "returns the existing run and its build for a duplicate client_run_id" do
      data = shard_payload(1)
      first = ingest(data)
      second = ingest(data)
      expect(second).to have_attributes(created: false, run: first.run)
      expect(second.run.build).to eq(first.run.build)
      expect(project.builds.count).to eq(1)
    end

    it "accepts a shard with a null total" do
      data = shard_payload(3).tap { |d| d["run"]["shard"]["total"] = nil }
      run = ingest(data).run
      expect(run).to have_attributes(shard_index: 3, shard_total: nil)
      expect(run.build.reload).to have_attributes(expected_shards: nil, status: "passed")
    end

    describe "pull request details" do
      let(:pr) { { "number" => 7, "base_branch" => "main", "head_branch" => "feat", "head_sha" => "def456" } }

      def with_pr(payload, repository: "acme/app", default_branch: "main", pr: self.pr)
        payload["run"]["ci"]["repository"] = repository if repository
        payload["run"]["git"]["default_branch"] = default_branch if default_branch
        payload["run"]["git"]["pr"] = pr if pr
        payload
      end

      it "stores them on the created build" do
        ingest(with_pr(shard_payload(1)))
        expect(project.builds.sole).to have_attributes(repository: "acme/app", default_branch: "main", pr_number: 7,
                                                       pr_base_branch: "main", pr_head_branch: "feat")
      end

      it "back-fills blank columns from a later shard" do
        ingest(shard_payload(1))
        expect(project.builds.sole).to have_attributes(repository: nil, default_branch: nil, pr_number: nil)
        ingest(with_pr(shard_payload(2)))
        expect(project.builds.sole).to have_attributes(repository: "acme/app", default_branch: "main", pr_number: 7,
                                                       pr_base_branch: "main", pr_head_branch: "feat")
      end

      it "never overwrites columns that are already set" do
        ingest(with_pr(shard_payload(1)))
        other = { "number" => 9, "base_branch" => "dev", "head_branch" => "other", "head_sha" => "zzz" }
        ingest(with_pr(shard_payload(2), repository: "evil/repo", default_branch: "dev", pr: other))
        expect(project.builds.sole).to have_attributes(repository: "acme/app", default_branch: "main", pr_number: 7,
                                                       pr_base_branch: "main", pr_head_branch: "feat")
      end

      it "never overwrites a non-blank column even when it is in the blanks hash" do
        ingest(shard_payload(1))
        stale = project.builds.sole
        stale.update_columns(repository: "acme/app")
        fresh = Build.find(stale.id)
        fresh.repository = nil # stale in-memory view: looks blank, DB already set
        described_class.new(project: project, payload: "{}", files: {})
                       .send(:backfill_build, fresh, with_pr(shard_payload(2), repository: "evil/repo"))
        expect(Build.find(stale.id)).to have_attributes(repository: "acme/app", pr_number: 7)
      end

      it "leaves PR columns blank for 0.2.0 payloads" do
        ingest(shard_payload(1))
        ingest(shard_payload(2))
        expect(project.builds.sole).to have_attributes(repository: nil, default_branch: nil, pr_number: nil,
                                                       pr_base_branch: nil, pr_head_branch: nil)
      end
    end
  end

  describe "concurrent shard uploads" do
    self.use_transactional_tests = false

    after do
      [ ActiveStorage::Attachment, ActiveStorage::Blob, TestResult, ErrorGroup, Run, Build, TestCase, ApiToken, Session, Project,
        Invitation, Membership, Organization, User ].each(&:delete_all)
    end

    def shard_data(index, status)
      build_payload(results: [ build_result("identifier" => "s#{index}", "full_name" => "Shard #{index}", "status" => status) ])
        .tap do |d|
          d["run"]["ci"]["build_key"] = "github_actions:acme/app:999:1"
          d["run"]["shard"] = { "index" => index, "total" => 2, "label" => "test##{index}" }
        end
    end

    def ingest_concurrently(payloads)
      project # create before the threads start
      gate = Queue.new
      threads = payloads.map do |data|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            gate.pop
            Ingest.call(project: project, payload: data.to_json, files: {})
          end
        end
      end
      payloads.size.times { gate << :go }
      threads.map(&:value)
    end

    it "attaches simultaneous shards of a new build to one build" do
      results = ingest_concurrently([ shard_data(1, "passed"), shard_data(2, "failed") ])

      expect(results.map(&:created)).to eq([ true, true ])
      expect(project.builds.count).to eq(1)
      build = project.builds.sole
      expect(build.runs.count).to eq(2)
      expect(build).to have_attributes(total_count: 2, passed_count: 1, failed_count: 1, status: "failed",
                                       expected_shards: 2)
    end

    it "returns the existing run for a simultaneous duplicate upload" do
      data = shard_data(1, "passed")
      results = ingest_concurrently([ data, data ])
      expect(results.map(&:created)).to contain_exactly(true, false)
      expect(results.map(&:run).uniq.size).to eq(1)
      expect(project.runs.count).to eq(1)
      expect(project.builds.sole.status).to eq("incomplete")
    end
  end

  describe "quarantined results" do
    let(:quarantined) do
      build_result("identifier" => "./spec/login_spec.rb[1:2]", "full_name" => "Login is flaky", "status" => "quarantined",
                   "failure" => { "message" => "Net::ReadTimeout", "exception_class" => "Net::ReadTimeout",
                                  "backtrace" => [ "spec/login_spec.rb:9" ] })
    end

    it "counts them separately, keeps their failure and groups it, and does not fail the run or build" do
      run = ingest(build_payload(schema_version: 2, results: [ build_result, quarantined ])).run

      expect(run).to have_attributes(status: "passed", schema_version: 2, total_count: 2, passed_count: 1,
                                     failed_count: 0, quarantined_count: 1)
      result = run.test_results.find_by!(status: "quarantined")
      expect(result).to have_attributes(failure_message: "Net::ReadTimeout", exception_class: "Net::ReadTimeout",
                                        backtrace: "spec/login_spec.rb:9")
      expect(result.error_group).to have_attributes(exception_class: "Net::ReadTimeout")
      expect(run.build.reload).to have_attributes(status: "passed", quarantined_count: 1, failed_count: 0)
      expect(project.test_cases.find_by!(full_name: "Login is flaky").last_status).to eq("quarantined")
    end

    it "fails the run when a real failure sits next to a quarantined one" do
      broken = build_result("identifier" => "./spec/login_spec.rb[1:3]", "full_name" => "Login is broken", "status" => "failed")
      run = ingest(build_payload(schema_version: 2, results: [ quarantined, broken ])).run

      expect(run).to have_attributes(status: "failed", failed_count: 1, quarantined_count: 1)
      expect(run.build.reload).to have_attributes(status: "failed", failed_count: 1, quarantined_count: 1)
    end
  end
end
