class CreateSavedViews < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_views do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :query, null: false, default: ""
      t.string :level, null: false, default: "tests"
      t.boolean :shared, null: false, default: false
      t.timestamps
    end
    add_index :saved_views, %i[project_id shared]
  end
end
