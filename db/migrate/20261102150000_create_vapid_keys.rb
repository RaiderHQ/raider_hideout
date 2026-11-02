class CreateVapidKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :vapid_keys do |t|
      t.string :name, null: false
      t.string :public_key, null: false
      t.text :private_key, null: false
      t.timestamps
    end
    add_index :vapid_keys, :name, unique: true
  end
end
