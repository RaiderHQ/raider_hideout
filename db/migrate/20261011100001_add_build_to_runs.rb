class AddBuildToRuns < ActiveRecord::Migration[8.1]
  # Frozen copy of the backfill: plain SQL, idempotent, independent of app code.
  module BackfillBuilds
    def self.call(connection)
      now = connection.quote(Time.current.utc.strftime("%Y-%m-%d %H:%M:%S.%6N"))
      connection.execute(<<~SQL)
        INSERT INTO builds (project_id, build_key, provider, build_id, ci_url, branch, commit_sha, commit_message,
                            status, total_count, passed_count, failed_count, skipped_count, pending_count, flaky_count,
                            started_at, finished_at, duration_ms, created_at, updated_at)
        SELECT r.project_id, 'run:' || r.client_run_id, r.ci_provider, r.ci_build_id, r.build_url, r.branch, r.commit_sha,
               r.commit_message, r.status, r.total_count, r.passed_count, r.failed_count, r.skipped_count,
               r.pending_count, r.flaky_count, r.started_at, r.finished_at, r.duration_ms, r.created_at, #{now}
        FROM runs r
        WHERE r.build_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM builds b WHERE b.project_id = r.project_id AND b.build_key = 'run:' || r.client_run_id)
      SQL
      connection.execute(<<~SQL)
        UPDATE runs SET build_id = (SELECT b.id FROM builds b
                                    WHERE b.project_id = runs.project_id AND b.build_key = 'run:' || runs.client_run_id)
        WHERE build_id IS NULL
      SQL
    end
  end

  def up
    # The existing CI id string moves to ci_build_id; build_id becomes the FK.
    if column_exists?(:runs, :build_id) && !column_exists?(:runs, :ci_build_id)
      rename_column :runs, :build_id, :ci_build_id
    end
    unless column_exists?(:runs, :build_id)
      add_reference :runs, :build, foreign_key: true, null: true
      add_column :runs, :shard_index, :integer
      add_column :runs, :shard_total, :integer
      add_column :runs, :shard_label, :string
    end
    BackfillBuilds.call(connection)
    change_column_null :runs, :build_id, false
  end

  def down
    remove_reference :runs, :build, foreign_key: true, index: true if column_exists?(:runs, :build_id)
    remove_column :runs, :shard_index if column_exists?(:runs, :shard_index)
    remove_column :runs, :shard_total if column_exists?(:runs, :shard_total)
    remove_column :runs, :shard_label if column_exists?(:runs, :shard_label)
    rename_column :runs, :ci_build_id, :build_id if column_exists?(:runs, :ci_build_id)
  end
end
