class CreateNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_deliveries do |t|
      t.references :notification_channel, null: false, foreign_key: true
      t.references :build, null: true, foreign_key: true
      t.string :kind, null: false
      t.json :events, null: false, default: []
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :sent_at

      t.timestamps
    end
    add_index :notification_deliveries, %i[notification_channel_id build_id], unique: true,
              where: "kind = 'build'", name: "index_notification_deliveries_once_per_build"
  end
end
