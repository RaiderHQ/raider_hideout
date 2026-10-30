class CreateTestCases < ActiveRecord::Migration[8.1]
  def change
    create_table :test_cases do |t|
      t.references :project, null: false, foreign_key: true
      t.string :test_key, null: false
      t.string :full_name, null: false
      t.string :file_path, null: false
      t.integer :line_number
      t.string :last_status
      t.boolean :flaky, null: false, default: false
      t.string :flaky_reason
      t.float :flip_rate, null: false, default: 0.0
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :test_cases, %i[project_id test_key], unique: true
    add_index :test_cases, %i[project_id flaky]
  end
end
