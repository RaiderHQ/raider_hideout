class Ingest
  MAX_ATTACHMENT_BYTES = 5.megabytes
  Result = Data.define(:run, :created)

  BACKFILL_COLUMNS = %i[repository default_branch pr_number pr_base_branch pr_head_branch pr_url].freeze

  class TooLarge < StandardError; end

  class Invalid < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("invalid payload")
    end
  end

  def self.call(...)
    new(...).call
  end

  def initialize(project:, payload:, files:)
    @project = project
    @raw_payload = payload
    @files = files
  end

  def call
    data = parse
    errors = PayloadValidator.new(data, @files.keys).errors
    raise Invalid, errors if errors.any?
    raise TooLarge if @files.values.any? { |file| file.size > MAX_ATTACHMENT_BYTES }

    existing = @project.runs.find_by(client_run_id: data["client_run_id"])
    return Result.new(run: existing, created: false) if existing

    run = persist(data)
    FlakinessJob.perform_later(run.id)
    attach_files(run, data["results"])
    Result.new(run: run, created: true)
  rescue ActiveRecord::RecordNotUnique
    Result.new(run: @project.runs.find_by!(client_run_id: data["client_run_id"]), created: false)
  end

  private

  def parse
    replace_nul(JSON.parse(@raw_payload.to_s))
  rescue JSON::ParserError => e
    raise Invalid, [ "payload is not valid JSON: #{e.message.truncate(120)}" ]
  end

  # NUL can't be stored by Postgres text columns or bound into SQLite upsert SQL;
  # replacing it before validation keeps test keys derived from the stored names.
  def replace_nul(value)
    case value
    when Hash then value.to_h { |k, v| [ replace_nul(k), replace_nul(v) ] }
    when Array then value.map { |v| replace_nul(v) }
    when String then value.tr("\u0000", "\u{FFFD}")
    else value
    end
  end

  def persist(data)
    results = data["results"]
    Run.transaction do
      build = find_or_create_build(data)
      backfill_build(build, data)
      run = @project.runs.create!(run_attributes(data).merge(build: build))
      case_ids = upsert_test_cases(results)
      insert_results(run, results, case_ids)
      group_failures(run, results)
      run.update!(count_attributes(results))
      build.recompute!
      run
    end
  end

  # Shards of one CI build arrive concurrently: the unique (project_id, build_key)
  # index decides the winner and the loser reads the winner's row.
  def find_or_create_build(data)
    key = data.dig("run", "ci", "build_key").presence || "run:#{data['client_run_id']}"
    @project.builds.find_by(build_key: key) ||
      @project.builds.create_or_find_by!(build_key: key) { |build| build.assign_attributes(build_attributes(data)) }
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.errors.of_kind?(:build_key, :taken)

    @project.builds.find_by!(build_key: key)
  end

  # Later shards may carry fields the first one lacked (e.g. PR details): fill
  # only columns that are still blank, never overwrite.
  def backfill_build(build, data)
    blanks = build_attributes(data).slice(*BACKFILL_COLUMNS).select { |_column, value| value.present? }
    return if blanks.empty?

    # One atomic statement: columns come from the fixed BACKFILL_COLUMNS list, never user input.
    assignments = blanks.keys.map do |column|
      raise ArgumentError, "unexpected column #{column}" unless BACKFILL_COLUMNS.include?(column)

      # NULLIF against '' only on string columns: Postgres rejects it on integers.
      current = Build.columns_hash[column.to_s].type == :string ? "NULLIF(#{column}, '')" : column.to_s
      "#{column} = COALESCE(#{current}, :#{column})"
    end
    Build.where(id: build.id).update_all([ assignments.join(", "), blanks ])
    build.reload
  end

  def build_attributes(data)
    git = data["run"]["git"] || {}
    ci = data["run"]["ci"] || {}
    pr = git["pr"].is_a?(Hash) ? git["pr"] : {}
    {
      repository: ci["repository"].presence, default_branch: git["default_branch"].presence,
      pr_number: pr["number"], pr_base_branch: pr["base_branch"].presence, pr_head_branch: pr["head_branch"].presence,
      pr_url: pr["url"].is_a?(String) ? safe_url(pr["url"]) : nil,
      provider: ci["provider"], build_id: ci["build_id"], attempt: ci["attempt"], ci_url: safe_url(ci["build_url"]),
      branch: git["branch"].presence, commit_sha: git["commit_sha"].presence, commit_message: git["commit_message"]
    }
  end

  def run_attributes(data)
    meta = data["run"]
    git = meta["git"] || {}
    ci = meta["ci"] || {}
    shard = meta["shard"] || {}
    started = parse_time(meta["started_at"])
    finished = parse_time(meta["finished_at"])
    {
      client_run_id: data["client_run_id"], schema_version: data["schema_version"],
      started_at: started, finished_at: finished,
      duration_ms: (started && finished ? ((finished - started) * 1000).round : nil),
      branch: git["branch"].presence, commit_sha: git["commit_sha"].presence, commit_message: git["commit_message"],
      ci_provider: ci["provider"], build_url: safe_url(ci["build_url"]), ci_build_id: ci["build_id"]&.to_s,
      environment: meta["environment"] || {},
      shard_index: shard["index"], shard_total: shard["total"], shard_label: shard["label"]
    }
  end

  def upsert_test_cases(results)
    now = Time.current
    rows = results.to_h do |r|
      key = TestCase.key_for(r["file_path"], r["full_name"])
      [ key, { project_id: @project.id, test_key: key, full_name: r["full_name"], file_path: r["file_path"],
              line_number: r["line_number"], last_status: r["status"], last_seen_at: now,
              created_at: now, updated_at: now } ]
    end.values
    TestCase.upsert_all(rows, unique_by: %i[project_id test_key],
                              update_only: %i[full_name file_path line_number last_status last_seen_at])
    @project.test_cases.where(test_key: rows.map { |r| r[:test_key] }).pluck(:test_key, :id).to_h
  end

  def insert_results(run, results, case_ids)
    now = Time.current
    rows = results.map do |r|
      failure = TestResult::FAILING_STATUSES.include?(r["status"]) ? (r["failure"] || {}) : {}
      attempts = [ r["attempts"].to_i, 1 ].max
      {
        run_id: run.id, test_case_id: case_ids.fetch(TestCase.key_for(r["file_path"], r["full_name"])),
        identifier: r["identifier"], status: r["status"], duration_ms: r["duration_ms"].to_i, attempts: attempts,
        retried_flaky: attempts > 1 && r["status"] == "passed", tags: r["tags"] || [],
        tags_text: TestResult.tags_text_for(r["tags"]),
        failure_message: failure["message"], exception_class: failure["exception_class"],
        backtrace: Array(failure["backtrace"]).join("\n").presence, app_frame: stored_app_frame(failure["app_frame"]),
        created_at: now, updated_at: now
      }
    end
    TestResult.insert_all(rows) if rows.any?
  end

  def stored_app_frame(frame)
    frame.is_a?(String) ? frame.first(ErrorGroup::SAMPLE_APP_FRAME_LIMIT).presence : nil
  end

  # Spec §4.3: `app_frame` is only in the payload, so inserted rows are matched back
  # by identifier and, for a repeated identifier, by insertion (id) order.
  def group_failures(run, results)
    failed = results.select { |r| TestResult::FAILING_STATUSES.include?(r["status"]) }
    return if failed.empty?

    app_frames = failed.group_by { |r| r["identifier"] }
                       .transform_values { |rs| rs.map { |r| (r["failure"] || {})["app_frame"] } }
    rows = run.test_results.where(status: TestResult::FAILING_STATUSES).order(:id)
              .pluck(:id, :identifier, :exception_class, :failure_message, :backtrace)
    tuples = rows.map do |id, identifier, klass, message, backtrace|
      ErrorGroup.tuple(id, klass, message, backtrace, app_frames[identifier]&.shift)
    end
    ErrorGroup.assign!(project: @project, results: tuples)
  end

  # Quarantined results never fail a run (spec §5.1).
  def count_attributes(results)
    counts = results.map { |r| r["status"] }.tally
    {
      total_count: results.size, passed_count: counts.fetch("passed", 0), failed_count: counts.fetch("failed", 0),
      skipped_count: counts.fetch("skipped", 0), pending_count: counts.fetch("pending", 0),
      quarantined_count: counts.fetch("quarantined", 0),
      flaky_count: results.count { |r| r["attempts"].to_i > 1 && r["status"] == "passed" },
      status: counts.fetch("failed", 0).positive? ? "failed" : "passed"
    }
  end

  def attach_files(run, results)
    by_identifier = run.test_results.index_by(&:identifier)
    results.each do |r|
      Array(r["attachments"]).each do |attachment|
        file = @files.fetch(attachment["part"])
        by_identifier.fetch(r["identifier"]).attachments.attach(
          io: file.respond_to?(:tempfile) ? file.tempfile : file, filename: file.original_filename,
          content_type: attachment["content_type"], metadata: { "name" => attachment["name"].to_s }
        )
      end
    end
  end

  def safe_url(value)
    uri = URI.parse(value.to_s)
    value.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  def parse_time(value)
    value.present? ? Time.iso8601(value) : nil
  end
end
