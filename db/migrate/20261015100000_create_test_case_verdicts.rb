class CreateTestCaseVerdicts < ActiveRecord::Migration[8.1]
  # Frozen copy of Flakiness::Analyzer::MIN_SAMPLES at the time of writing, so a
  # copied verdict is trusted as the default branch's own verdict.
  MIN_SAMPLES = 5

  # Plain SQL through the migration's connection, independent of app models.
  #
  # The test_case foreign key is added only after the test_cases columns are gone:
  # SQLite drops and rebuilds test_cases to remove a column, and inside the migration's
  # transaction foreign keys cannot be switched off, so ON DELETE CASCADE would wipe
  # every copied verdict. `down` removes it first for the same reason.
  def up
    create_table :test_case_verdicts do |t|
      t.references :test_case, null: false, index: false
      t.string :branch, null: false
      t.boolean :flaky, null: false, default: false
      t.string :flaky_reason
      t.float :flip_rate
      t.integer :sample_count, null: false, default: 0
      t.references :flaky_since_build, foreign_key: { to_table: :builds, on_delete: :nullify }, null: true
      t.timestamps
    end
    add_index :test_case_verdicts, %i[test_case_id branch], unique: true
    add_index :test_case_verdicts, %i[branch flaky]

    now = connection.quote(Time.current.utc)
    execute <<~SQL
      INSERT INTO test_case_verdicts (test_case_id, branch, flaky, flaky_reason, flip_rate, sample_count,
                                      flaky_since_build_id, created_at, updated_at)
      SELECT tc.id, #{default_branch_sql('tc.project_id')}, tc.flaky, tc.flaky_reason, tc.flip_rate, #{MIN_SAMPLES},
             tc.flaky_since_build_id, #{now}, #{now}
      FROM test_cases tc
      WHERE tc.flaky = #{connection.quoted_true} OR tc.flaky_reason IS NOT NULL
         OR tc.flaky_since_build_id IS NOT NULL OR tc.flip_rate > 0
    SQL

    remove_index :test_cases, %i[project_id flaky]
    remove_reference :test_cases, :flaky_since_build, foreign_key: { to_table: :builds, on_delete: :nullify }, index: true
    remove_column :test_cases, :flaky
    remove_column :test_cases, :flaky_reason
    remove_column :test_cases, :flip_rate
    add_foreign_key :test_case_verdicts, :test_cases, on_delete: :cascade
  end

  def down
    # Restores only each test case's default-branch verdict; other branches' rows are dropped.
    remove_foreign_key :test_case_verdicts, :test_cases, on_delete: :cascade
    add_column :test_cases, :flaky, :boolean, null: false, default: false
    add_column :test_cases, :flaky_reason, :string
    add_column :test_cases, :flip_rate, :float, null: false, default: 0.0
    add_reference :test_cases, :flaky_since_build, foreign_key: { to_table: :builds, on_delete: :nullify }, null: true
    add_index :test_cases, %i[project_id flaky]

    verdict = <<~SQL.squish
      FROM test_case_verdicts v
      WHERE v.test_case_id = test_cases.id AND v.branch = #{default_branch_sql('test_cases.project_id')}
    SQL
    execute <<~SQL
      UPDATE test_cases
      SET flaky = (SELECT v.flaky #{verdict}),
          flaky_reason = (SELECT v.flaky_reason #{verdict}),
          flip_rate = COALESCE((SELECT v.flip_rate #{verdict}), 0.0),
          flaky_since_build_id = (SELECT v.flaky_since_build_id #{verdict})
      WHERE EXISTS (SELECT 1 #{verdict})
    SQL

    drop_table :test_case_verdicts
  end

  private

  # Project#default_branch (spec §4.5) for the project id expression given.
  def default_branch_sql(project_id)
    <<~SQL.squish
      COALESCE(
        (SELECT b.default_branch FROM builds b
         WHERE b.project_id = #{project_id} AND b.default_branch IS NOT NULL AND b.default_branch <> ''
         ORDER BY b.created_at DESC, b.id DESC LIMIT 1),
        CASE
          WHEN EXISTS (SELECT 1 FROM builds b WHERE b.project_id = #{project_id} AND b.branch = 'main') THEN 'main'
          WHEN EXISTS (SELECT 1 FROM builds b WHERE b.project_id = #{project_id} AND b.branch = 'master') THEN 'master'
          ELSE 'main'
        END
      )
    SQL
  end
end
