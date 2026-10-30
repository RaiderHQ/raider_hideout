class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.string :role, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :invitations, %i[organization_id email], unique: true,
                                                       where: "accepted_at IS NULL AND revoked_at IS NULL",
                                                       name: "index_invitations_one_pending_per_email"
  end
end
