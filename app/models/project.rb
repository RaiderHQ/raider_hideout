class Project < ApplicationRecord
  include Sluggable

  belongs_to :organization
  has_many :api_tokens, dependent: :destroy
  has_many :builds, dependent: :destroy
  has_many :runs, dependent: :destroy
  has_many :quarantines, dependent: :delete_all
  has_many :test_cases, dependent: :destroy
  has_many :error_groups, dependent: :destroy
  has_many :notification_channels, dependent: :destroy
  has_many :saved_views, dependent: :delete_all
  has_one :gate_rule, dependent: :delete

  CONVENTIONAL_BRANCHES = %w[main master].freeze

  validates :name, presence: true

  def recent_builds(limit = 30)
    builds.includes(:project, :runs).order(created_at: :desc, id: :desc).limit(limit)
  end

  def latest_build
    builds.order(created_at: :desc, id: :desc).first
  end

  def average_pass_rate(recent = recent_builds)
    rates = recent.map(&:pass_rate).compact
    rates.any? ? (rates.sum.to_f / rates.size).round : nil
  end

  def average_duration_ms(recent = recent_builds)
    durations = recent.map(&:duration_ms).compact
    durations.any? ? (durations.sum.to_f / durations.size).round : nil
  end

  def flaky_count
    TestCaseVerdict.where(test_case_id: test_cases.select(:id), branch: default_branch, flaky: true).count
  end

  # The one answer to "does this project gate its builds?" (an all-off rule counts as no).
  def gate_enabled?
    gate_rule&.enabled? || false
  end

  # The most recent build's reported default branch, else main/master by usage.
  def default_branch
    @default_branch ||= builds.where.not(default_branch: [ nil, "" ]).order(created_at: :desc, id: :desc).pick(:default_branch) ||
                        conventional_branch || "main"
  end

  # "main" if any build ran on main, else "master" if any ran on master, else nil.
  def conventional_branch
    used = builds.where(branch: CONVENTIONAL_BRANCHES).distinct.pluck(:branch)
    CONVENTIONAL_BRANCHES.find { |branch| used.include?(branch) }
  end
end
