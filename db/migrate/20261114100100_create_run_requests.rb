class CreateRunRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :run_requests do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :ref, null: false
      t.string :tags
      t.string :repository, null: false
      t.string :workflow, null: false
      t.string :status, null: false
      t.integer :http_status
      t.string :message
      t.string :github_run_id
      t.string :html_url
      t.timestamps
    end
    add_index :run_requests, [ :project_id, :created_at ]
    add_index :run_requests, [ :project_id, :github_run_id ]
    add_index :builds, [ :project_id, :build_id ]
  end
end
