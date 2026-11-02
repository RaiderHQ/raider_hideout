# Which events a user wants on their phone. Defaults come from the column defaults.
class PushPreference < ApplicationRecord
  SWITCHES = %i[default_branch_failures new_flaky gate_failures rerun_results].freeze

  belongs_to :user
end
