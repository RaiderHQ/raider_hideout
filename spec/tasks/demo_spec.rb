require "rails_helper"
require "rake"

RSpec.describe "hideout:demo" do
  include ActiveSupport::Testing::TimeHelpers

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "hideout:demo" } }

  let(:task) { Rake::Task["hideout:demo"] }

  def invoke
    task.reenable
    expect { task.invoke }.to output(/Demo data loaded/).to_stdout
  end

  def counts
    [ User, Organization, Membership, Project, Build, Run, TestResult, RunRequest, CiAccess, ActiveStorage::Attachment ].map(&:count)
  end

  it "loads the demo project and leaves the same counts when run again" do
    invoke
    first = counts
    invoke
    expect(counts).to eq(first)

    project = Project.find_by!(name: "Shop tests")
    expect(project.organization.name).to eq("Demo")
    expect(project.builds.pluck(:status).sort).to eq(%w[failed passed])
    failed = project.builds.find_by!(status: "failed")
    result = failed.runs.first.test_results.find_by!(status: "failed")
    expect(result.attachments.map { |a| a.blob.content_type }).to eq([ Ingest::TRACE_CONTENT_TYPE ])
    expect(project.ci_access).to be_run_tests_ready
    expect(project.ci_access).to have_attributes(repository: "raider-demo/shop-tests", workflow: "test_pipeline.yml", tag_input: "tags")
    requests = RunRequest.recent(project).to_a
    expect(requests.map(&:state_copy)).to contain_exactly("Build ##{failed.id}", "waiting for results",
                                                          "GitHub rejected the token. Replace it in CI access.")
  end

  it "re-stamps the requests so the 24-hour panel shows them days later" do
    travel_to(3.days.ago) { invoke }
    expect(RunRequest.recent(Project.find_by!(name: "Shop tests"))).to be_empty
    invoke
    expect(RunRequest.recent(Project.find_by!(name: "Shop tests")).size).to eq(3)
  end

  it "refuses to run in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    task.reenable
    expect { task.invoke }.to raise_error(SystemExit).and output(/only in development and test/).to_stderr
    expect(User.count).to eq(0)
  end
end
