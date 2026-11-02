class AddStepsToTestResults < ActiveRecord::Migration[8.1]
  def change
    add_column :test_results, :steps, :json
  end
end
