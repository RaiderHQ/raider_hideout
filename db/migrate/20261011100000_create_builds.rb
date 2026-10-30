class CreateBuilds < ActiveRecord::Migration[8.1]
  def change
    create_table :builds do |t|
      t.references :project, null: false, foreign_key: true
      t.string :build_key, null: false
      t.string :provider
      t.string :build_id
      t.string :attempt
      t.string :ci_url
      t.string :branch
      t.string :commit_sha
      t.string :commit_message
      t.string :status, null: false, default: "passed"
      t.integer :expected_shards
      t.integer :total_count, null: false, default: 0
      t.integer :passed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :pending_count, null: false, default: 0
      t.integer :flaky_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_ms
      t.timestamps
    end
    add_index :builds, [ :project_id, :build_key ], unique: true
    add_index :builds, [ :project_id, :branch, :created_at ]
  end
end
