class ErrorGroup < ApplicationRecord
  SAMPLE_MESSAGE_LIMIT = 10_000
  SAMPLE_APP_FRAME_LIMIT = 500
  BACKFILL_BATCH_SIZE = 1_000

  # On conflict: first/last seen only widen (a backfill of older results can move
  # first_seen_at earlier but never last_seen_at back), the sample follows the
  # latest failure, and a nil app frame never replaces a known one. The CASE
  # form runs on both SQLite and Postgres; SET expressions read the pre-update row.
  ON_CONFLICT = Arel.sql(<<~SQL.squish)
    first_seen_at = CASE WHEN excluded.first_seen_at < error_groups.first_seen_at
                         THEN excluded.first_seen_at ELSE error_groups.first_seen_at END,
    last_seen_at = CASE WHEN excluded.last_seen_at > error_groups.last_seen_at
                        THEN excluded.last_seen_at ELSE error_groups.last_seen_at END,
    sample_message = CASE WHEN excluded.last_seen_at >= error_groups.last_seen_at
                          THEN excluded.sample_message ELSE error_groups.sample_message END,
    sample_app_frame = CASE WHEN excluded.last_seen_at >= error_groups.last_seen_at
                            THEN COALESCE(excluded.sample_app_frame, error_groups.sample_app_frame)
                            ELSE COALESCE(error_groups.sample_app_frame, excluded.sample_app_frame) END,
    updated_at = excluded.updated_at
  SQL

  belongs_to :project
  has_many :test_results, dependent: :nullify

  # Groups failed results by signature digest. `results` holds
  # [test_result_id, Failures::Signature::Result, raw_message, app_frame, seen_at]
  # tuples; seen_at is optional (now when nil; the backfill passes the run's
  # created_at). The latest tuple of each digest supplies the sample. One upsert
  # per distinct digest, then one update per group links the results.
  def self.assign!(project:, results:)
    return if results.empty?

    now = Time.current
    by_digest = results.group_by { |(_id, signature)| signature.digest }
    by_digest.each_value { |tuples| upsert_group(project, tuples, now) }

    ids = where(project_id: project.id, digest: by_digest.keys).pluck(:digest, :id).to_h
    by_digest.each do |digest, tuples|
      TestResult.where(id: tuples.map(&:first)).update_all(error_group_id: ids.fetch(digest))
    end
    nil
  end

  def self.upsert_group(project, tuples, now)
    seen = tuples.map { |tuple| tuple[4] || now }
    _id, signature, raw_message, app_frame = tuples[seen.each_with_index.max_by { |time, i| [ time, i ] }.last]
    upsert_all([ {
      project_id: project.id, digest: signature.digest, exception_class: signature.exception_class,
      normalized_message: signature.normalized_message, frame: signature.frame,
      sample_message: raw_message&.to_s&.first(SAMPLE_MESSAGE_LIMIT),
      sample_app_frame: app_frame.is_a?(String) ? app_frame.first(SAMPLE_APP_FRAME_LIMIT).presence : nil,
      first_seen_at: seen.min, last_seen_at: seen.max, created_at: now, updated_at: now
    } ], unique_by: %i[project_id digest], on_duplicate: ON_CONFLICT, record_timestamps: false)
  end
  private_class_method :upsert_group

  # Groups failed results that predate clustering (spec §4.3). Idempotent: only
  # results with no group are read. Seen times come from the runs' created_at.
  # Returns [groups created, results linked].
  def self.backfill!(batch_size: BACKFILL_BATCH_SIZE)
    groups_before = count
    linked = 0
    Project.find_each do |project|
      TestResult.joins(:run).where(runs: { project_id: project.id }, status: "failed", error_group_id: nil)
                .in_batches(of: batch_size) do |batch|
        rows = batch.pluck(:id, :exception_class, :failure_message, :backtrace, "runs.created_at")
        tuples = rows.map { |id, klass, message, backtrace, seen_at| tuple(id, klass, message, backtrace, nil, seen_at) }
        assign!(project: project, results: tuples)
        linked += rows.size
      end
    end
    [ count - groups_before, linked ]
  end

  def self.tuple(id, exception_class, message, backtrace, app_frame = nil, seen_at = nil)
    signature = Failures::Signature.for(exception_class: exception_class, message: message,
                                        app_frame: app_frame, backtrace: backtrace)
    [ id, signature, message, app_frame, seen_at ]
  end
end
