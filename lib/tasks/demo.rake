# Demo data for trying Hideout by hand and for the Raider app's Simulator smoke run.
# Development and test only; safe to run again (it finds what it made before).
namespace :hideout do
  desc "Load demo data: demo@raider.test / raider-demo-password, project Shop tests (development and test only)"
  task demo: :environment do
    abort "hideout:demo runs only in development and test." unless Rails.env.development? || Rails.env.test?

    Hideout::Demo.load!
    puts "Demo data loaded. Sign in as #{Hideout::Demo::EMAIL} / #{Hideout::Demo::PASSWORD}."
  end
end

module Hideout
  # The records hideout:demo creates. Builds arrive through Ingest, as a reporter upload would.
  module Demo
    EMAIL = "demo@raider.test".freeze
    PASSWORD = "raider-demo-password".freeze
    REPOSITORY = "raider-demo/shop-tests".freeze
    TOKEN = "ghp_#{'0' * 36}".freeze # The right shape for CI access; GitHub would refuse it.
    TRACE = Rails.root.join("spec/fixtures/files/trace-v1.zip")

    module_function

    def load!
      raise "hideout:demo runs only in development and test." unless Rails.env.development? || Rails.env.test?

      user = demo_user
      organization = Organization.find_or_create_by!(name: "Demo", personal: false)
      organization.memberships.find_or_create_by!(user: user) { |m| m.role = "owner" }
      project = organization.projects.find_or_create_by!(name: "Shop tests")
      passed = ingest(project, run_id: "9001", sha: "a1b2c3d", message: "Show the basket total", failed: false)
      failed = ingest(project, run_id: "9002", sha: "e4f5a6b", message: "Pay by card on checkout", failed: true)
      ci_access(project)
      run_requests(project, user, failed)
      { user: user, project: project, builds: [ passed, failed ] }
    end

    def demo_user
      user = User.find_or_initialize_by(email_address: EMAIL)
      user.password = PASSWORD if user.new_record?
      user.email_verified_at ||= Time.current
      user.save!
      Organization.create_personal!(user) unless user.personal_organization
      user
    end

    def ingest(project, run_id:, sha:, message:, failed:)
      files = {}
      results = [ result("./spec/basket_spec.rb[1:1]", "Basket shows the total", "spec/basket_spec.rb", "passed") ]
      if failed
        files["trace"] = upload(TRACE)
        results << result("./spec/checkout_spec.rb[1:1]", "Checkout pays by card", "spec/checkout_spec.rb", "failed").merge(
          "failure" => { "message" => "Unable to find button \"Pay\"", "exception_class" => "Capybara::ElementNotFound",
                         "backtrace" => [ "spec/checkout_spec.rb:12:in 'block (2 levels) in <top (required)>'" ] },
          "steps" => { "items" => [ { "id" => "s1", "title" => "Open https://shop.test/checkout" },
                                    { "id" => "s2", "title" => "Click \"Pay\"" } ], "failed" => 1 },
          "attachments" => [ { "part" => "trace", "content_type" => Ingest::TRACE_CONTENT_TYPE, "name" => "trace" } ]
        )
      end
      payload = {
        "schema_version" => 2, "client_run_id" => "hideout-demo-#{run_id}",
        "run" => {
          "started_at" => "2026-11-14T09:00:00Z", "finished_at" => "2026-11-14T09:01:30Z",
          "ci" => { "provider" => "github_actions", "build_id" => run_id, "repository" => REPOSITORY, "attempt" => "1",
                    "build_url" => "https://github.com/#{REPOSITORY}/actions/runs/#{run_id}" },
          "git" => { "branch" => "main", "default_branch" => "main", "commit_sha" => sha, "commit_message" => message },
          "environment" => { "ruby" => RUBY_VERSION, "browser" => "chrome" }
        },
        "results" => results
      }
      Ingest.call(project: project, payload: payload.to_json, files: files).run.build
    end

    def result(identifier, name, file, status)
      { "identifier" => identifier, "full_name" => name, "file_path" => file, "line_number" => 4, "status" => status,
        "duration_ms" => 1200, "attempts" => 1, "tags" => [], "attachments" => [] }
    end

    def upload(path)
      tempfile = Tempfile.new([ "demo-trace", ".zip" ], binmode: true)
      tempfile.write(File.binread(path))
      tempfile.rewind
      ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: "trace.zip", type: Ingest::TRACE_CONTENT_TYPE)
    end

    def ci_access(project)
      access = project.ci_access || project.build_ci_access
      access.token = TOKEN if access.new_record?
      access.token_saved_at ||= Time.current
      access.update!(repository: REPOSITORY, workflow: "test_pipeline.yml", tag_input: "tags")
    end

    # Three requests, re-stamped to the last few minutes on every run so the 24-hour panel shows them.
    def run_requests(project, user, failed_build)
      rows = [
        { ref: "main", tags: nil, status: "accepted", http_status: 200, github_run_id: failed_build.build_id, ago: 6.minutes },
        { ref: "main", tags: "@smoke", status: "accepted", http_status: 200, github_run_id: "9003", ago: 4.minutes },
        { ref: "release/2.0", tags: nil, status: "rejected", http_status: 401, github_run_id: nil, ago: 2.minutes }
      ]
      rows.each do |row|
        request = project.run_requests.find_or_initialize_by(ref: row[:ref], tags: row[:tags], status: row[:status])
        run_id = row[:github_run_id]
        request.assign_attributes(user: user, repository: REPOSITORY, workflow: "test_pipeline.yml", http_status: row[:http_status],
                                  message: (row[:status] == "rejected" ? "Bad credentials" : nil), github_run_id: run_id,
                                  html_url: run_id && "https://github.com/#{REPOSITORY}/actions/runs/#{run_id}",
                                  created_at: row[:ago].ago)
        request.save!
      end
    end
  end
end
