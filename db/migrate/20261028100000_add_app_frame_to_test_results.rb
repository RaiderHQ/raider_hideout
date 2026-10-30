class AddAppFrameToTestResults < ActiveRecord::Migration[8.1]
  def change
    add_column :test_results, :app_frame, :string, limit: 500
  end
end
