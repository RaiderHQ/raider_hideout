class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :client_run_id, null: false
      t.integer :schema_version, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_ms
      t.string :branch
      t.string :commit_sha
      t.string :commit_message
      t.string :ci_provider
      t.string :build_url
      t.string :build_id
      t.json :environment, null: false, default: {}
      t.string :status, null: false, default: "passed"
      t.integer :total_count, null: false, default: 0
      t.integer :passed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :pending_count, null: false, default: 0
      t.integer :flaky_count, null: false, default: 0
      t.timestamps
    end
    add_index :runs, %i[project_id client_run_id], unique: true
    add_index :runs, %i[project_id branch created_at]
  end
end
