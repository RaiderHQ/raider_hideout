class Run < ApplicationRecord
  belongs_to :project
  belongs_to :build
  has_many :test_results, dependent: :destroy
  has_many :test_cases, -> { distinct }, through: :test_results

  after_create_commit -> { broadcast_prepend_later_to [ project, :runs ], target: "runs", partial: "runs/run", locals: { run: self } }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # "rspec#10" after "rspec#2", "rspec#1.2" after "rspec#1.1"; unlabelled runs last.
  def self.in_shard_order(runs)
    runs.sort_by do |run|
      prefix, index = run.shard_label.to_s.split("#", 2)
      [ run.shard_label.nil? ? 1 : 0, prefix.to_s, index.to_s.split(".").map(&:to_i), run.shard_index || 0, run.id ]
    end
  end

  # Quarantined results do not fail the build but do count as not passing.
  def pass_rate
    executed = passed_count + failed_count + quarantined_count
    return nil if executed.zero?

    (passed_count * 100.0 / executed).round
  end
end
