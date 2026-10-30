class AddTagsTextToTestResults < ActiveRecord::Migration[8.1]
  # Fills tags_text for rows stored before the column existed. Done in Ruby so no
  # JSON SQL function is needed on either database (spec §4.4).
  module Backfill
    def self.call(conn, batch: 1000)
      last_id = 0
      loop do
        rows = conn.select_rows("SELECT id, tags FROM test_results WHERE id > #{last_id.to_i} ORDER BY id LIMIT #{batch.to_i}")
        break if rows.empty?

        rows.each do |id, tags|
          text = TestResult.tags_text_for(decode(tags))
          conn.update("UPDATE test_results SET tags_text = #{conn.quote(text)} WHERE id = #{id.to_i}") unless text.empty?
        end
        last_id = rows.last.first.to_i
      end
    end

    def self.decode(tags)
      return tags if tags.is_a?(Array)

      JSON.parse(tags.to_s)
    rescue JSON::ParserError
      []
    end
  end

  def up
    add_column :test_results, :tags_text, :string, null: false, default: ""
    add_index :test_results, %i[run_id status]
    Backfill.call(connection)
  end

  def down
    remove_index :test_results, %i[run_id status]
    remove_column :test_results, :tags_text
  end
end
