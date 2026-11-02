class CreatePushSubscriptionsAndPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.string :p256dh
      t.string :auth
      t.string :device_label
      t.datetime :last_success_at
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true

    create_table :push_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :default_branch_failures, null: false, default: true
      t.boolean :rerun_results, null: false, default: true
      t.boolean :new_flaky, null: false, default: false
      t.boolean :gate_failures, null: false, default: false
      t.timestamps
    end

    create_table :push_muted_projects do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :push_muted_projects, %i[user_id project_id], unique: true
  end
end
