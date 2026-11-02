class AddTestResultsRunTestCaseIndex < ActiveRecord::Migration[8.1]
  # Backs the supersession EXISTS lookup (same run, same test); also covers run_id-only lookups.
  def change
    add_index :test_results, [ :run_id, :test_case_id ]
    remove_index :test_results, :run_id, name: "index_test_results_on_run_id"
  end
end
