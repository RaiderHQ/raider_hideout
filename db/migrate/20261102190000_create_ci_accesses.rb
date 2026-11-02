class CreateCiAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :ci_accesses do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :provider, null: false, default: "github"
      t.text :token, null: false
      t.datetime :token_saved_at, null: false
      t.datetime :checked_at
      t.boolean :check_ok
      t.string :check_message
      t.timestamps
    end
  end
end
