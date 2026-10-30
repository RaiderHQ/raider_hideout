class AddFlakySinceBuildToTestCases < ActiveRecord::Migration[8.1]
  def change
    add_reference :test_cases, :flaky_since_build, foreign_key: { to_table: :builds, on_delete: :nullify }, null: true
  end
end
