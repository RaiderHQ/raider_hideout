class AddPullRequestFieldsToBuilds < ActiveRecord::Migration[8.1]
  def change
    change_table :builds, bulk: true do |t|
      t.string :repository
      t.string :default_branch
      t.integer :pr_number
      t.string :pr_base_branch
      t.string :pr_head_branch
    end
    add_index :builds, %i[project_id pr_number]
  end
end
