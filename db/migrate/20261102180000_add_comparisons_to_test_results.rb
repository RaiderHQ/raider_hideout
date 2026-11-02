class AddComparisonsToTestResults < ActiveRecord::Migration[8.1]
  def change
    add_column :test_results, :comparisons, :json
  end
end
