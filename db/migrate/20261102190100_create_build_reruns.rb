class CreateBuildReruns < ActiveRecord::Migration[8.1]
  def change
    create_table :build_reruns do |t|
      t.references :build, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.integer :attempt_before, null: false
      t.string :status, null: false
      t.integer :http_status
      t.string :message
      t.timestamps
    end
    add_index :build_reruns, [ :build_id, :created_at ]
  end
end
