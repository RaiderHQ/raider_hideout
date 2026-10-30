# A project's quality gate (spec §4.1): three rules, each off by default. The row is
# created on the first save; builds evaluated afterwards use the values then saved.
class GateRule < ApplicationRecord
  belongs_to :project
  belongs_to :updated_by, class_name: "User", optional: true

  validates :project_id, uniqueness: true
  validates :min_pass_rate, numericality: { only_integer: true, in: 1..100 }, allow_nil: true

  def enabled?
    min_pass_rate.present? || no_new_failures || no_new_flaky
  end
end
