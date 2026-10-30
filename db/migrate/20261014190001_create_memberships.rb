class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :organization, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :memberships, %i[organization_id user_id], unique: true
  end
end
