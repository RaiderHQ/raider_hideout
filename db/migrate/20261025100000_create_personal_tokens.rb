class CreatePersonalTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false, limit: 8
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :personal_tokens, :token_digest, unique: true
  end
end
