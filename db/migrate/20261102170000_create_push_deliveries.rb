class CreatePushDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :push_deliveries do |t|
      t.references :push_subscription, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :build, null: false, foreign_key: { on_delete: :cascade }
      t.integer :attempt, null: false, default: 1
      t.timestamps
    end
    add_index :push_deliveries, %i[push_subscription_id build_id attempt], unique: true, name: "index_push_deliveries_uniqueness"
  end
end
