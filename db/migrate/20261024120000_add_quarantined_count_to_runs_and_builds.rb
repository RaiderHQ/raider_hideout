class AddQuarantinedCountToRunsAndBuilds < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :quarantined_count, :integer, null: false, default: 0
    add_column :builds, :quarantined_count, :integer, null: false, default: 0
  end
end
