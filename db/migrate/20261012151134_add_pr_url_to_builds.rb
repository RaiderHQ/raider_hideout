class AddPrUrlToBuilds < ActiveRecord::Migration[8.1]
  def change
    add_column :builds, :pr_url, :string
  end
end
