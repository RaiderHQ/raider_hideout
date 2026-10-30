class AddFlakinessAnalyzedAtToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :flakiness_analyzed_at, :datetime
  end
end
