require "rails_helper"

RSpec.describe QuarantineEvent do
  let(:quarantine) { create(:quarantine) }

  it "is insert-only" do
    event = quarantine.events.create!(action: "quarantined", actor: quarantine.created_by, expires_at: quarantine.expires_at)
    expect { event.update!(note: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(event.reload.note).to be_nil
  end

  it "accepts the four actions only and a note up to 500 characters" do
    QuarantineEvent::ACTIONS.each do |action|
      expect(quarantine.events.new(action: action, expires_at: quarantine.expires_at)).to be_valid
    end
    expect(quarantine.events.new(action: "deleted", expires_at: quarantine.expires_at)).not_to be_valid
    expect(quarantine.events.new(action: "released", expires_at: quarantine.expires_at, note: "x" * 501)).not_to be_valid
  end

  it "lists a project's events newest first" do
    older = quarantine.events.create!(action: "quarantined", expires_at: quarantine.expires_at, created_at: 2.days.ago)
    newer = quarantine.events.create!(action: "extended", expires_at: quarantine.expires_at, created_at: 1.day.ago)
    create(:quarantine).events.create!(action: "quarantined", expires_at: 1.day.from_now)

    expect(described_class.for_project(quarantine.project).newest_first).to eq([ newer, older ])
  end
end
