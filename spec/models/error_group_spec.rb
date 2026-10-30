require "rails_helper"

RSpec.describe ErrorGroup do
  let(:project) { create(:project) }
  let(:run) { create(:run, project: project) }

  def failed_result(message = "boom")
    create(:test_result, run: run, status: "failed", exception_class: "RuntimeError", failure_message: message)
  end

  def tuple(result, app_frame = nil)
    ErrorGroup.tuple(result.id, result.exception_class, result.failure_message, result.backtrace, app_frame)
  end

  describe ".assign!" do
    it "creates one group per digest and links each result" do
      a = failed_result("waited 1s")
      b = failed_result("waited 2s")
      c = failed_result("other")
      expect(described_class.assign!(project: project, results: [ tuple(a), tuple(b), tuple(c, "spec/a.rb:1:in 'x'") ])).to be_nil
      expect(project.error_groups.count).to eq(2)
      expect(a.reload.error_group).to eq(b.reload.error_group)
      expect(c.reload.error_group.sample_app_frame).to eq("spec/a.rb:1:in 'x'")
      expect(a.error_group).to have_attributes(sample_message: "waited 2s", normalized_message: "waited <n>s", frame: "")
    end

    it "keeps a known sample_app_frame when a later failure has none" do
      first = failed_result
      described_class.assign!(project: project, results: [ tuple(first, "spec/a.rb:1:in 'x'") ])
      later = failed_result.tap { |r| r.update!(backtrace: "/w/spec/a.rb:5:in 'x'") } # same frame, no app_frame
      described_class.assign!(project: project, results: [ tuple(later) ])
      expect(later.reload.error_group).to have_attributes(id: first.reload.error_group_id,
                                                           sample_app_frame: "spec/a.rb:1:in 'x'")
    end

    it "truncates the sample message to 10,000 characters" do
      result = failed_result("x" * 20_000)
      described_class.assign!(project: project, results: [ tuple(result) ])
      expect(result.reload.error_group.sample_message.length).to eq(10_000)
    end

    it "does nothing for no results" do
      expect { described_class.assign!(project: project, results: []) }.not_to change(described_class, :count)
    end
  end

  it "keeps results when a group is destroyed" do
    result = failed_result
    described_class.assign!(project: project, results: [ tuple(result) ])
    result.reload.error_group.destroy!
    expect(result.reload.error_group_id).to be_nil
  end

  it "nullifies results at the database level when a group row is deleted" do
    result = failed_result
    described_class.assign!(project: project, results: [ tuple(result) ])
    described_class.delete_all
    expect(result.reload.error_group_id).to be_nil
  end

  it "is destroyed with its project" do
    result = failed_result
    described_class.assign!(project: project, results: [ tuple(result) ])
    expect { project.destroy! }.to change(described_class, :count).by(-1)
  end

  it "keeps the newer last_seen_at and sample when an older failure arrives later" do
    newer_at = 1.day.ago.change(usec: 0)
    older_at = 3.days.ago.change(usec: 0)
    described_class.assign!(project: project, results: [ tuple(failed_result("waited 1s")).tap { |t| t[4] = newer_at } ])
    described_class.assign!(project: project, results: [ tuple(failed_result("waited 3s")).tap { |t| t[4] = older_at } ])

    expect(described_class.sole).to have_attributes(first_seen_at: older_at, last_seen_at: newer_at, sample_message: "waited 1s")
  end
end
