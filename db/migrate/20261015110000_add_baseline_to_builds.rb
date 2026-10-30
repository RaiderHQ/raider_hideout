class AddBaselineToBuilds < ActiveRecord::Migration[8.1]
  def change
    add_reference :builds, :baseline_build, foreign_key: { to_table: :builds, on_delete: :nullify }, null: true
    add_column :builds, :baseline_assigned_at, :datetime
  end
end
