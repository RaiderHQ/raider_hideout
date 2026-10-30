require "rails_helper"

RSpec.describe TestCaseVerdict do
  let(:project) { create(:project) }
  let(:test_case) { create(:test_case, project: project) }

  def verdict(branch, **attrs)
    create(:test_case_verdict, { test_case: test_case, branch: branch }.merge(attrs))
  end

  it "requires a branch, unique per test case" do
    verdict("main")
    expect(build(:test_case_verdict, test_case: test_case, branch: "")).not_to be_valid
    expect(build(:test_case_verdict, test_case: test_case, branch: "main")).not_to be_valid
    expect(build(:test_case_verdict, test_case: test_case, branch: "feature")).to be_valid
  end

  it "is deleted with its test case" do
    row = verdict("main")
    test_case.destroy!
    expect(described_class.exists?(row.id)).to be(false)
  end

  describe "TestCase#verdict_for" do
    it "uses the branch's own row once it has enough samples" do
      verdict("feature", flaky: true, flaky_reason: "flips", flip_rate: 0.4, sample_count: 5)
      verdict("main", flaky: false, sample_count: 20)
      expect(test_case.verdict_for("feature", default_branch: "main"))
        .to eq(Verdict.new(flaky: true, reason: "flips", flip_rate: 0.4, source: :branch))
    end

    it "trusts an own flaky row with only 2 samples" do
      verdict("feature", flaky: true, flaky_reason: "same_commit", flip_rate: 1.0, sample_count: 2)
      verdict("main", flaky: false, sample_count: 20)
      expect(test_case.verdict_for("feature", default_branch: "main"))
        .to eq(Verdict.new(flaky: true, reason: "same_commit", flip_rate: 1.0, source: :branch))
    end

    it "falls back to a flaky default branch over an own not-flaky row with 2 samples" do
      verdict("feature", flaky: false, sample_count: 2)
      verdict("main", flaky: true, flaky_reason: "retry", flip_rate: 0.2, sample_count: 12)
      expect(test_case.verdict_for("feature", default_branch: "main"))
        .to eq(Verdict.new(flaky: true, reason: "retry", flip_rate: 0.2, source: :default_branch))
    end

    it "keeps an own not-flaky row with 5 samples over a flaky default branch" do
      verdict("feature", flaky: false, flip_rate: 0.0, sample_count: 5)
      verdict("main", flaky: true, flaky_reason: "retry", sample_count: 12)
      expect(test_case.verdict_for("feature", default_branch: "main"))
        .to have_attributes(flaky: false, source: :branch)
    end

    it "reports none without rows" do
      expect(test_case.verdict_for("feature", default_branch: "main")).to eq(Verdict::NONE)
      expect(Verdict::NONE).to have_attributes(flaky: false, source: :none)
    end

    it "reports none for a thin not-flaky default-branch row looked up on the default branch itself" do
      verdict("main", flaky: false, sample_count: 3)
      expect(test_case.verdict_for("main", default_branch: "main").source).to eq(:none)
    end

    it "reports the default branch's own row as :branch once it has enough samples" do
      verdict("main", flaky: true, flaky_reason: "same_commit", sample_count: 5)
      expect(test_case.verdict_for("main", default_branch: "main"))
        .to have_attributes(flaky: true, source: :branch)
    end

    it "uses the default branch for a build without a branch" do
      verdict("main", flaky: true, flaky_reason: "flips", sample_count: 5)
      expect(test_case.verdict_for(nil, default_branch: "main").source).to eq(:default_branch)
      expect(test_case.verdict_for(nil, default_branch: nil)).to eq(Verdict::NONE)
    end
  end

  describe ".for_cases" do
    it "resolves twenty test cases in at most two queries" do
      cases = create_list(:test_case, 20, project: project)
      cases.each_with_index do |tc, i|
        create(:test_case_verdict, test_case: tc, branch: "feature", flaky: i < 10 && i.even?, sample_count: i < 10 ? 5 : 2)
        create(:test_case_verdict, test_case: tc, branch: "main", flaky: true, sample_count: 5)
      end
      ids = cases.map(&:id)

      queries = 0
      counter = ->(*, payload) { queries += 1 unless %w[SCHEMA CACHE TRANSACTION].include?(payload[:name]) }
      result = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.for_cases(ids, branch: "feature", default_branch: "main")
      end

      expect(queries).to be <= 2
      expect(result.keys).to match_array(ids)
      expect(ids.first(10).map { |id| result[id].source }).to all(eq(:branch))
      expect(ids.first(10).map { |id| result[id].flaky }).to eq([ true, false ] * 5)
      expect(ids.last(10).map { |id| result[id] }).to all(have_attributes(source: :default_branch, flaky: true))
    end

    it "maps ids without rows to none, also when given a relation" do
      other = create(:test_case, project: project)
      verdict("main", flaky: true)
      result = described_class.for_cases(TestCase.where(project: project).select(:id), branch: "main", default_branch: "main")
      expect(result[test_case.id]).to have_attributes(flaky: true, source: :branch)
      expect(result[other.id]).to eq(Verdict::NONE)
    end
  end
end
