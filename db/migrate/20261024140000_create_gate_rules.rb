class CreateGateRules < ActiveRecord::Migration[8.1]
  def change
    create_table :gate_rules do |t|
      t.references :project, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.integer :min_pass_rate
      t.boolean :no_new_failures, null: false, default: false
      t.boolean :no_new_flaky, null: false, default: false
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
  end
end
