class AddDroppedAttachmentsToTestResults < ActiveRecord::Migration[8.1]
  def change
    add_column :test_results, :dropped_attachments, :json, default: [], null: false
  end
end
