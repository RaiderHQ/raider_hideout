class CreateNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_channels do |t|
      t.references :project, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.text :webhook_url
      t.text :recipients
      t.boolean :include_owner, null: false, default: true
      t.string :branch_filter, null: false, default: "default"
      t.string :branch_pattern
      t.boolean :on_failed, null: false, default: true
      t.boolean :on_recovered, null: false, default: true
      t.boolean :on_new_flaky, null: false, default: false
      t.integer :pass_rate_below

      t.timestamps
    end
    add_index :notification_channels, %i[project_id kind]
  end
end
