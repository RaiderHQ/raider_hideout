class TestCase < ApplicationRecord
  belongs_to :project
  has_many :test_results, dependent: :destroy
  has_many :verdicts, class_name: "TestCaseVerdict", dependent: :delete_all
  has_many :quarantines, dependent: :delete_all

  REASONS = {
    "same_commit" => "Passed and failed on the same commit",
    "retry" => "Passed only after a retry",
    "flips" => "Status flips often between runs"
  }.freeze

  def self.key_for(file_path, full_name)
    Digest::SHA256.hexdigest("#{file_path}\0#{full_name}")
  end

  def verdict_for(branch, default_branch:)
    TestCaseVerdict.for_cases([ id ], branch: branch, default_branch: default_branch)[id]
  end

  def flaky_reason_text(reason)
    REASONS[reason]
  end
end
