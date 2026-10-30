class CreateTestResults < ActiveRecord::Migration[8.1]
  def change
    create_table :test_results do |t|
      t.references :run, null: false, foreign_key: true
      t.references :test_case, null: false, foreign_key: true
      t.string :identifier, null: false
      t.string :status, null: false
      t.integer :duration_ms, null: false, default: 0
      t.integer :attempts, null: false, default: 1
      t.boolean :retried_flaky, null: false, default: false
      t.json :tags, null: false, default: []
      t.text :failure_message
      t.string :exception_class
      t.text :backtrace
      t.timestamps
    end
    add_index :test_results, %i[test_case_id created_at]
  end
end
