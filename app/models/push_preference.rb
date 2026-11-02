# Which events a user wants on their phone. Defaults come from the column defaults.
# rerun_results is stored now but not shown or sent until re-runs exist (slice 2).
class PushPreference < ApplicationRecord
  SWITCHES = %i[default_branch_failures new_flaky gate_failures].freeze

  belongs_to :user
end
