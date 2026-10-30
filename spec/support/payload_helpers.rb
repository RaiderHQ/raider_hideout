module PayloadHelpers
  def build_result(**overrides)
    {
      "identifier" => "./spec/login_spec.rb[1:1]", "full_name" => "Login works", "file_path" => "spec/login_spec.rb",
      "line_number" => 3, "status" => "passed", "duration_ms" => 120, "attempts" => 1, "tags" => [ "smoke" ],
      "attachments" => []
    }.merge(overrides.transform_keys(&:to_s))
  end

  def build_payload(results: [ build_result ], **overrides)
    {
      "schema_version" => 1,
      "client_run_id" => SecureRandom.uuid,
      "run" => {
        "started_at" => "2026-10-10T12:00:00Z", "finished_at" => "2026-10-10T12:00:05Z",
        "ci" => { "provider" => "github_actions", "build_url" => "https://ci/1", "build_id" => "1" },
        "git" => { "branch" => "main", "commit_sha" => "abc", "commit_message" => "Fix" },
        "environment" => { "ruby" => "4.0.2" }
      },
      "results" => results
    }.merge(overrides.transform_keys(&:to_s))
  end

  def upload_file(name = "shot.png", bytes = "PNG", content_type = "image/png")
    file = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: name)
  end
end

RSpec.configure { |c| c.include PayloadHelpers }
