class AddRunTestsToCiAccesses < ActiveRecord::Migration[8.1]
  def change
    add_column :ci_accesses, :repository, :string
    add_column :ci_accesses, :workflow, :string
    add_column :ci_accesses, :tag_input, :string
  end
end
