require "rails_helper"
require Rails.root.join("db/migrate/20261011100001_add_build_to_runs").to_s

RSpec.describe "build backfill" do
  let(:project) { create(:project) }
  let(:conn) { ActiveRecord::Base.connection }

  def insert_buildless_run(client_run_id, **cols)
    run = create(:run, project: project, client_run_id: client_run_id, **cols)
    conn.execute("UPDATE runs SET build_id = NULL WHERE id = #{run.id}")
    conn.execute("DELETE FROM builds WHERE id = #{run.build_id}")
    run.id
  end

  # The column is NOT NULL after migrating; relax it for the pre-backfill state.
  around do |example|
    conn.change_column_null :runs, :build_id, true
    example.run
  ensure
    conn.change_column_null :runs, :build_id, false
  end

  it "gives every buildless run its own build and is idempotent" do
    a = insert_buildless_run("alpha", branch: "main", commit_sha: "aaa", passed_count: 3, total_count: 3,
                                      ci_provider: "github_actions", ci_build_id: "42", build_url: "https://ci/42")
    b = insert_buildless_run("beta", status: "failed", failed_count: 1, total_count: 1)

    AddBuildToRuns::BackfillBuilds.call(conn)
    AddBuildToRuns::BackfillBuilds.call(conn)

    expect(Build.where(project: project).pluck(:build_key)).to contain_exactly("run:alpha", "run:beta")
    run_a = Run.find(a)
    expect(run_a.build).to have_attributes(build_key: "run:alpha", branch: "main", commit_sha: "aaa", total_count: 3,
                                           passed_count: 3, provider: "github_actions", build_id: "42",
                                           ci_url: "https://ci/42", status: "passed")
    expect(Run.find(b).build).to have_attributes(build_key: "run:beta", status: "failed", failed_count: 1)
    expect(Run.find(a).build_id).not_to eq(Run.find(b).build_id)
  end

  it "leaves runs that already have a build alone" do
    run = create(:run, project: project, client_run_id: "keep")
    original = run.build_id
    AddBuildToRuns::BackfillBuilds.call(conn)
    expect(run.reload.build_id).to eq(original)
    expect(Build.where(build_key: "run:keep")).to be_empty
  end

  it "migration up is idempotent on a migrated schema" do
    run = create(:run, project: project)
    expect { ActiveRecord::Migration.suppress_messages { AddBuildToRuns.new.migrate(:up) } }.not_to change { [ Build.count, run.reload.build_id ] }
  end
end
