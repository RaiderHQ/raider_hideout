class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :projects, :slug, unique: true
  end
end
