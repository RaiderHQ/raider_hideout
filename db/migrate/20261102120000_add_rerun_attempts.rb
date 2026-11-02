class AddRerunAttempts < ActiveRecord::Migration[8.1]
  # Migration-local model: the backfill must not depend on app models.
  class MigrationBuild < ActiveRecord::Base
    self.table_name = "builds"
    self.inheritance_column = nil
  end

  module Backfill
    def self.call
      MigrationBuild.reset_column_information
      # Only the attempt-1 build of a run owns the key; the unique index would reject a second claimant.
      MigrationBuild.where(provider: "github_actions").find_each do |build|
        # Literal ":1" suffix: from_build_key maps "01" or out-of-range attempts to 1 as well.
        next unless build.build_key.to_s.end_with?(":1")

        key, = Builds::RunKey.from_build_key(build.build_key)
        build.update_columns(ci_run_key: key) if key
      end
      MigrationBuild.where.not(gate_evaluated_at: nil).update_all(gate_attempt: 1)
    end
  end

  def up
    add_column :builds, :ci_run_key, :string
    add_column :builds, :latest_attempt, :integer, null: false, default: 1
    add_column :builds, :gate_attempt, :integer
    add_column :runs, :attempt, :integer, null: false, default: 1
    add_column :test_results, :superseded, :boolean, null: false, default: false
    add_column :notification_deliveries, :attempt, :integer, null: false, default: 1

    add_index :builds, [ :project_id, :ci_run_key ], unique: true, where: "ci_run_key IS NOT NULL",
                                                     name: "index_builds_on_project_id_and_ci_run_key"
    add_index :runs, [ :build_id, :attempt ]
    remove_index :notification_deliveries, name: "index_notification_deliveries_once_per_build"
    add_index :notification_deliveries, [ :notification_channel_id, :build_id, :attempt ], unique: true,
              where: "kind = 'build'", name: "index_notification_deliveries_once_per_build"

    Backfill.call
  end

  def down
    remove_index :notification_deliveries, name: "index_notification_deliveries_once_per_build"
    add_index :notification_deliveries, [ :notification_channel_id, :build_id ], unique: true,
              where: "kind = 'build'", name: "index_notification_deliveries_once_per_build"
    remove_index :runs, [ :build_id, :attempt ]
    remove_index :builds, name: "index_builds_on_project_id_and_ci_run_key"

    remove_column :notification_deliveries, :attempt
    remove_column :test_results, :superseded
    remove_column :runs, :attempt
    remove_column :builds, :gate_attempt
    remove_column :builds, :latest_attempt
    remove_column :builds, :ci_run_key
  end
end
