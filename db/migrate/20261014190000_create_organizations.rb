class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.boolean :personal, null: false, default: false
      t.references :personal_owner, foreign_key: { to_table: :users }, index: { unique: true }
      t.timestamps
    end
  end
end
