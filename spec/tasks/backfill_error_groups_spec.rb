require "rails_helper"
require "rake"

RSpec.describe "raider:backfill_error_groups" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "raider:backfill_error_groups" } }

  let(:task) { Rake::Task["raider:backfill_error_groups"] }

  def failed_result(run, message, backtrace = "/home/runner/work/x/x/spec/pages/login_page.rb:42:in 'click'")
    create(:test_result, run: run, status: "failed", exception_class: "RuntimeError", failure_message: message,
                         backtrace: backtrace)
  end

  def invoke(expected = /\AError groups created: \d+; results linked: \d+\n\z/)
    task.reenable
    expect { task.invoke }.to output(expected).to_stdout
  end

  it "groups failed results that have no group, per project" do
    run = create(:run)
    other_run = create(:run)
    same = Array.new(3) { |i| failed_result(run, "waited #{i}s") }
    unique = failed_result(run, "different")
    elsewhere = failed_result(other_run, "waited 9s")
    passed = create(:test_result, run: run, status: "passed")

    invoke("Error groups created: 3; results linked: 5\n")

    expect(same.map { |r| r.reload.error_group_id }.uniq.size).to eq(1)
    expect(unique.reload.error_group_id).not_to eq(same.first.error_group_id)
    expect(elsewhere.reload.error_group.project).to eq(other_run.project)
    expect(same.first.error_group).to have_attributes(project: run.project, frame: "spec/pages/login_page.rb:in click")
    expect(passed.reload.error_group_id).to be_nil
  end

  describe "seen times" do
    include ActiveSupport::Testing::TimeHelpers

    def old_failure(at, message)
      travel_to(at) { failed_result(create(:run, project: project), message) }
    end

    let(:project) { create(:project) }
    let(:three_days_ago) { 3.days.ago.change(usec: 0) }
    let(:one_day_ago) { 1.day.ago.change(usec: 0) }

    it "uses the earliest and latest run times of the grouped results" do
      old_failure(one_day_ago, "waited 1s")
      old_failure(three_days_ago, "waited 3s")

      invoke

      expect(project.error_groups.sole).to have_attributes(first_seen_at: three_days_ago, last_seen_at: one_day_ago,
                                                           sample_message: "waited 1s")
    end

    it "only moves first_seen_at earlier and keeps a newer sample when the group already exists" do
      old_failure(three_days_ago, "waited 3s")
      Ingest.call(project: project, files: {}, payload: build_payload(results: [
        build_result("status" => "failed", "failure" => {
          "message" => "waited 0s", "exception_class" => "RuntimeError", "app_frame" => "spec/pages/login_page.rb:9:in 'click'",
          "backtrace" => [ "/home/runner/work/x/x/spec/pages/login_page.rb:42:in 'click'" ]
        })
      ]).to_json)
      group = project.error_groups.sole
      ingested_at = group.last_seen_at

      invoke

      expect(group.reload).to have_attributes(first_seen_at: three_days_ago, last_seen_at: ingested_at,
                                              sample_message: "waited 0s",
                                              sample_app_frame: "spec/pages/login_page.rb:9:in 'click'")
    end

    it "keeps the earlier first_seen_at across batches" do
      stub_const("ErrorGroup::BACKFILL_BATCH_SIZE", 1)
      old_failure(one_day_ago, "waited 1s")
      old_failure(three_days_ago, "waited 3s")

      invoke

      expect(project.error_groups.sole).to have_attributes(first_seen_at: three_days_ago, last_seen_at: one_day_ago,
                                                           sample_message: "waited 1s")
    end
  end

  it "leaves already grouped results alone" do
    run = create(:run)
    group = create(:error_group, project: run.project)
    grouped = failed_result(run, "boom")
    grouped.update_column(:error_group_id, group.id)

    invoke

    expect(grouped.reload.error_group_id).to eq(group.id)
    expect(ErrorGroup.count).to eq(1)
  end

  it "makes no changes on a second run" do
    run = create(:run)
    2.times { |i| failed_result(run, "error #{i}") }
    invoke
    snapshot = [ ErrorGroup.order(:id).pluck(:id, :updated_at), TestResult.order(:id).pluck(:id, :error_group_id) ]

    invoke("Error groups created: 0; results linked: 0\n")
    expect([ ErrorGroup.order(:id).pluck(:id, :updated_at), TestResult.order(:id).pluck(:id, :error_group_id) ]).to eq(snapshot)
  end

  it "works per project in batches of 1,000" do
    expect(ErrorGroup::BACKFILL_BATCH_SIZE).to eq(1_000)
    stub_const("ErrorGroup::BACKFILL_BATCH_SIZE", 2)
    first, second = create(:run), create(:run)
    results = Array.new(5) { |i| failed_result(first, "case #{i}") } + [ failed_result(second, "case 9") ]
    expect(ErrorGroup).to receive(:assign!).with(project: first.project, results: satisfy { |r| r.size <= 2 })
                                           .exactly(3).times.and_call_original
    expect(ErrorGroup).to receive(:assign!).with(project: second.project, results: satisfy { |r| r.size == 1 })
                                           .once.and_call_original

    invoke

    expect(results.map { |r| r.reload.error_group_id }.uniq.size).to eq(2)
    expect(ErrorGroup.count).to eq(2)
  end
end
