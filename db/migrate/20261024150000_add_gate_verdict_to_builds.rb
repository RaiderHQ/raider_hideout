class AddGateVerdictToBuilds < ActiveRecord::Migration[8.1]
  # A lean model so the backfill does not depend on Build's callbacks.
  class MigrationBuild < ActiveRecord::Base
    self.table_name = "builds"
  end

  # Builds that exist when the gate ships were never under a rule (gate_rules is new),
  # so their verdict is "none"; left null they would read as pending forever.
  module Backfill
    NONE_RESULT = '{"rules":{}}'.freeze

    def self.call(now: Time.current)
      MigrationBuild.reset_column_information
      MigrationBuild.where(gate_evaluated_at: nil).update_all(gate_status: "none", gate_result: NONE_RESULT, gate_evaluated_at: now)
    end
  end

  def up
    add_column :builds, :gate_status, :string
    add_column :builds, :gate_result, :text
    add_column :builds, :gate_evaluated_at, :datetime
    Backfill.call
  end

  def down
    remove_column :builds, :gate_evaluated_at
    remove_column :builds, :gate_result
    remove_column :builds, :gate_status
  end
end
