require "rails_helper"
require Rails.root.join("db/migrate/20261024100000_add_tags_text_to_test_results").to_s

RSpec.describe "tags_text backfill" do
  let(:project) { create(:project) }
  let(:run) { create(:run, project: project) }
  let(:test_case) { create(:test_case, project: project) }

  def stored(tags)
    TestResult.create!(run: run, test_case: test_case, identifier: SecureRandom.hex(4), status: "passed", tags: tags)
  end

  it "fills tags_text for existing rows across batches and is idempotent" do
    tagged = stored([ "Smoke", "slow test", "a|b" ])
    plain = stored([])
    later = stored([ "Login" ])

    2.times { AddTagsTextToTestResults::Backfill.call(ActiveRecord::Base.connection, batch: 2) }

    expect(tagged.reload.tags_text).to eq("|smoke|slow test|ab|")
    expect(plain.reload.tags_text).to eq("")
    expect(later.reload.tags_text).to eq("|login|")
  end
end
