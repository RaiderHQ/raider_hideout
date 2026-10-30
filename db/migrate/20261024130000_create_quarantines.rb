class CreateQuarantines < ActiveRecord::Migration[8.1]
  def change
    create_table :quarantines do |t|
      t.references :project, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :test_case, null: false, foreign_key: { on_delete: :cascade }
      t.string :reason, null: false
      t.datetime :expires_at, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :released_at
      t.references :released_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :quarantines, %i[project_id expires_at]

    # Insert-only audit trail (spec §5.2): no updated_at.
    create_table :quarantine_events do |t|
      t.references :quarantine, null: false, foreign_key: { on_delete: :cascade }
      t.string :action, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :expires_at, null: false
      t.string :note
      t.datetime :created_at, null: false
    end
  end
end
