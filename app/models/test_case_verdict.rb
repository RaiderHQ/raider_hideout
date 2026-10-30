class TestCaseVerdict < ApplicationRecord
  belongs_to :test_case
  belongs_to :flaky_since_build, class_name: "Build", optional: true

  validates :branch, presence: true, uniqueness: { scope: :test_case_id }

  # One query for any number of test cases. `ids` may be an Array or a relation
  # selecting test case ids; ids without a usable verdict map to Verdict::NONE.
  def self.for_cases(ids, branch:, default_branch:)
    fallback = default_branch.presence
    fallback = nil if fallback == branch
    result = Hash.new(Verdict::NONE)
    branches = [ branch.presence, fallback ].compact
    if branches.any?
      where(test_case_id: ids, branch: branches).group_by(&:test_case_id).each do |id, rows|
        result[id] = resolve(rows, branch, fallback)
      end
    end
    ids.each { |id| result[id] = Verdict::NONE unless result.key?(id) } if ids.is_a?(Array)
    result
  end

  # The flaky list (FlakyTestsController and the API, spec §5.9): flaky verdicts of a project's
  # tests on one branch, highest flip rate first.
  def self.flaky_on(project, branch)
    joins(:test_case).where(test_cases: { project_id: project.id }, branch: branch, flaky: true)
                     .order(flip_rate: :desc).order(TestCase.arel_table[:full_name].asc).order(:id)
  end

  def self.resolve(rows, branch, fallback)
    own = rows.find { |row| row.branch == branch }
    # A positive flaky verdict is conclusive at any sample count; a thin "not flaky" is not.
    return own.to_verdict(:branch) if own && (own.flaky || own.sample_count >= Flakiness::Analyzer::MIN_SAMPLES)

    default = fallback && rows.find { |row| row.branch == fallback }
    default ? default.to_verdict(:default_branch) : Verdict::NONE
  end
  private_class_method :resolve

  def to_verdict(source)
    Verdict.new(flaky: flaky, reason: flaky_reason, flip_rate: flip_rate, source: source)
  end
end
