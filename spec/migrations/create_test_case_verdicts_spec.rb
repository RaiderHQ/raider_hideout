require "rails_helper"
require Dir[Rails.root.join("db/migrate/*_create_test_case_verdicts.rb")].first

# Runs the real migration against a throwaway in-memory SQLite database seeded with
# the pre-verdicts schema, so the test DB's schema is never touched. Each direction
# runs inside a transaction, like `db:migrate`, where SQLite cannot switch foreign
# keys off while it rebuilds a table.
RSpec.describe CreateTestCaseVerdicts do
  memory_db = Class.new(ActiveRecord::Base) do
    self.abstract_class = true

    def self.name = "CreateTestCaseVerdictsSpecDb"
  end

  let(:conn) { memory_db.lease_connection }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages do
      conn.transaction { described_class.new.exec_migration(conn, direction) }
    end
  end

  def rows(sql) = conn.select_all(sql).to_a

  def insert_project(name)
    conn.insert("INSERT INTO projects (name, created_at, updated_at) VALUES (#{conn.quote(name)}, '2026-10-01', '2026-10-01')")
  end

  def insert_build(project_id, branch:, default_branch: nil, at: "2026-10-01")
    conn.insert("INSERT INTO builds (project_id, branch, default_branch, created_at, updated_at) " \
                "VALUES (#{project_id}, #{conn.quote(branch)}, #{conn.quote(default_branch)}, '#{at}', '#{at}')")
  end

  def insert_case(project_id, name, flaky: false, reason: nil, flip_rate: 0.0, since: nil)
    conn.insert("INSERT INTO test_cases (project_id, test_key, full_name, flaky, flaky_reason, flip_rate, " \
                "flaky_since_build_id, created_at, updated_at) VALUES (#{project_id}, #{conn.quote(name)}, " \
                "#{conn.quote(name)}, #{flaky ? 1 : 0}, #{conn.quote(reason)}, #{flip_rate}, " \
                "#{since || 'NULL'}, '2026-10-01', '2026-10-01')")
  end

  before do
    memory_db.establish_connection(adapter: "sqlite3", database: ":memory:")
    conn.create_table(:projects) do |t|
      t.string :name, null: false
      t.timestamps
    end
    conn.create_table(:builds) do |t|
      t.references :project, null: false, foreign_key: true
      t.string :branch
      t.string :default_branch
      t.timestamps
    end
    conn.create_table(:test_cases) do |t|
      t.references :project, null: false, foreign_key: true
      t.string :test_key, null: false
      t.string :full_name, null: false
      t.boolean :flaky, null: false, default: false
      t.string :flaky_reason
      t.float :flip_rate, null: false, default: 0.0
      t.timestamps
    end
    conn.add_index :test_cases, %i[project_id flaky]
    conn.create_table(:test_results) do |t|
      t.references :test_case, null: false, foreign_key: true
      t.string :status, null: false
    end
    conn.add_reference :test_cases, :flaky_since_build, foreign_key: { to_table: :builds, on_delete: :nullify }, null: true
  end

  after { memory_db.remove_connection }

  it "copies flaky data to one verdict per test case on the project's default branch and reverses cleanly" do
    reported = insert_project("Reported")
    insert_build(reported, branch: "feature", default_branch: "develop", at: "2026-10-01")
    since = insert_build(reported, branch: "feature", default_branch: "trunk", at: "2026-10-02")
    master_only = insert_project("Master")
    insert_build(master_only, branch: "master")
    no_builds = insert_project("Empty")

    flaky = insert_case(reported, "flaky", flaky: true, reason: "same_commit", flip_rate: 0.5, since: since)
    healed = insert_case(reported, "healed", flip_rate: 0.1)
    stable = insert_case(reported, "stable")
    on_master = insert_case(master_only, "retry", flaky: true, reason: "retry", flip_rate: 0.25)
    orphan = insert_case(no_builds, "flips", flaky: true, reason: "flips", flip_rate: 0.4)

    conn.insert("INSERT INTO test_results (test_case_id, status) VALUES (#{flaky}, 'failed')")
    result_rows = "SELECT test_case_id, status FROM test_results"

    migrate(:up)

    expect(rows(result_rows)).to eq([ { "test_case_id" => flaky, "status" => "failed" } ])
    expect(rows("SELECT test_case_id, branch, flaky, flaky_reason, flip_rate, sample_count, flaky_since_build_id " \
                "FROM test_case_verdicts ORDER BY test_case_id"))
      .to eq([
        { "test_case_id" => flaky, "branch" => "trunk", "flaky" => 1, "flaky_reason" => "same_commit", "flip_rate" => 0.5,
          "sample_count" => Flakiness::Analyzer::MIN_SAMPLES, "flaky_since_build_id" => since },
        { "test_case_id" => healed, "branch" => "trunk", "flaky" => 0, "flaky_reason" => nil, "flip_rate" => 0.1,
          "sample_count" => Flakiness::Analyzer::MIN_SAMPLES, "flaky_since_build_id" => nil },
        { "test_case_id" => on_master, "branch" => "master", "flaky" => 1, "flaky_reason" => "retry", "flip_rate" => 0.25,
          "sample_count" => Flakiness::Analyzer::MIN_SAMPLES, "flaky_since_build_id" => nil },
        { "test_case_id" => orphan, "branch" => "main", "flaky" => 1, "flaky_reason" => "flips", "flip_rate" => 0.4,
          "sample_count" => Flakiness::Analyzer::MIN_SAMPLES, "flaky_since_build_id" => nil }
      ])
    expect(rows("SELECT id FROM test_cases ORDER BY id").map { |r| r["id"] }).to eq([ flaky, healed, stable, on_master, orphan ])
    %w[flaky flaky_reason flip_rate flaky_since_build_id].each do |column|
      expect(conn.column_exists?(:test_cases, column)).to be(false), "#{column} survived"
    end
    expect(conn.foreign_keys(:test_cases).map(&:to_table)).to eq([ "projects" ])
    expect(conn.foreign_keys(:test_results).map(&:to_table)).to eq([ "test_cases" ])
    expect(conn.foreign_keys(:test_case_verdicts).to_h { |fk| [ fk.to_table, fk.on_delete ] })
      .to eq("test_cases" => :cascade, "builds" => :nullify)
    expect(conn.index_exists?(:test_case_verdicts, %i[test_case_id branch], unique: true)).to be(true)

    migrate(:down)

    expect(rows(result_rows)).to eq([ { "test_case_id" => flaky, "status" => "failed" } ])
    expect(conn.foreign_keys(:test_results).map(&:to_table)).to eq([ "test_cases" ])
    expect(conn.table_exists?(:test_case_verdicts)).to be(false)
    expect(rows("SELECT id, flaky, flaky_reason, flip_rate, flaky_since_build_id FROM test_cases ORDER BY id"))
      .to eq([
        { "id" => flaky, "flaky" => 1, "flaky_reason" => "same_commit", "flip_rate" => 0.5, "flaky_since_build_id" => since },
        { "id" => healed, "flaky" => 0, "flaky_reason" => nil, "flip_rate" => 0.1, "flaky_since_build_id" => nil },
        { "id" => stable, "flaky" => 0, "flaky_reason" => nil, "flip_rate" => 0.0, "flaky_since_build_id" => nil },
        { "id" => on_master, "flaky" => 1, "flaky_reason" => "retry", "flip_rate" => 0.25, "flaky_since_build_id" => nil },
        { "id" => orphan, "flaky" => 1, "flaky_reason" => "flips", "flip_rate" => 0.4, "flaky_since_build_id" => nil }
      ])
    expect(conn.index_exists?(:test_cases, %i[project_id flaky])).to be(true)
    expect(conn.foreign_keys(:test_cases).map(&:to_table)).to contain_exactly("projects", "builds")
  end

  it "picks main over master when the project has builds on both and reports no default" do
    project = insert_project("Both")
    insert_build(project, branch: "master")
    insert_build(project, branch: "main")
    insert_case(project, "flaky", flaky: true, reason: "flips", flip_rate: 0.3)

    migrate(:up)

    expect(rows("SELECT branch FROM test_case_verdicts")).to eq([ { "branch" => "main" } ])
  end
end
