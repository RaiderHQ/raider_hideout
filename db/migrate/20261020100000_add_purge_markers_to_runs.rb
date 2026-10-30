class AddPurgeMarkersToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :attachments_purged_at, :datetime
    add_column :runs, :results_purged_at, :datetime
    add_index :runs, :created_at
  end
end
