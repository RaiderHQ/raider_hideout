class AddTokenToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :token, :text
  end
end
