class CreateErrorGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :error_groups do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.string :digest, null: false
      t.string :exception_class, null: false
      t.string :normalized_message, null: false
      t.string :frame, null: false, default: ""
      t.text :sample_message
      t.string :sample_app_frame
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :error_groups, %i[project_id digest], unique: true

    add_reference :test_results, :error_group, foreign_key: { on_delete: :nullify }, null: true, index: false
    add_index :test_results, %i[error_group_id created_at]
  end
end
