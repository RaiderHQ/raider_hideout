require "rails_helper"

RSpec.describe Quarantine do
  include ActiveSupport::Testing::TimeHelpers

  let(:project) { create(:project) }
  let(:test_case) { create(:test_case, project: project) }
  let(:user) { create(:user) }
  let(:now) { Time.zone.parse("2026-10-24 12:00:00") }

  around { |example| travel_to(now) { example.run } }

  def quarantine!(days: 14, reason: "Waits on the mail server", target: test_case)
    described_class.quarantine!(test_case: target, user: user, reason: reason, days: days)
  end

  describe ".quarantine!" do
    it "creates an active quarantine for the chosen days with a quarantined event" do
      q = quarantine!(days: "7")

      expect(q).to have_attributes(project: project, test_case: test_case, created_by: user, reason: "Waits on the mail server",
                                   expires_at: now + 7.days, released_at: nil)
      expect(q).to be_active
      expect(q.events.pluck(:action, :actor_id, :expires_at, :note)).to eq([ [ "quarantined", user.id, now + 7.days, nil ] ])
    end

    it "accepts each of 7, 14 and 30 days and nothing else" do
      described_class::DURATIONS.each do |days|
        expect(quarantine!(days: days, target: create(:test_case, project: project)).expires_at).to eq(now + days.days)
      end
      [ 0, 1, 15, 45, "abc", nil ].each do |days|
        expect { quarantine!(days: days, target: create(:test_case, project: project)) }
          .to raise_error(ActiveRecord::RecordInvalid, /Duration must be 7, 14 or 30 days/)
      end
    end

    it "requires a reason of 1 to 500 characters, stripped" do
      expect { quarantine!(reason: "  ") }.to raise_error(ActiveRecord::RecordInvalid, /Reason can't be blank/)
      expect { quarantine!(reason: "x" * 501) }.to raise_error(ActiveRecord::RecordInvalid, /Reason is too long/)
      expect(quarantine!(reason: "  #{'x' * 500}  ").reason.length).to eq(500)
    end

    it "allows one active quarantine per test case" do
      first = quarantine!
      expect { quarantine! }.to raise_error(described_class::AlreadyQuarantined) { |e| expect(e.quarantine).to eq(first) }
      expect(described_class.count).to eq(1)
    end

    it "allows a new quarantine once the old one expired or was released" do
      quarantine!(days: 7)
      travel 8.days
      expect(quarantine!).to be_active
      described_class.active.sole.release!(user: user)
      expect(quarantine!).to be_active
      expect(test_case.quarantines.count).to eq(3)
    end

    it "also refuses a second active one through the model validation" do
      quarantine!
      duplicate = described_class.new(project: project, test_case: test_case, reason: "again", expires_at: 1.day.from_now)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:test_case]).to eq([ "is already quarantined" ])
    end
  end

  describe ".active" do
    it "is unreleased and not yet expired" do
      live = quarantine!(days: 7)
      expect(described_class.active).to eq([ live ])
      expect(described_class.active(now + 7.days)).to be_empty
      expect(live.active?(now + 7.days - 1.second)).to be(true)
      live.release!(user: user)
      expect(described_class.active).to be_empty
    end
  end

  describe "#extend_by!" do
    it "sets expires_at to now plus the chosen days and records the note" do
      q = quarantine!(days: 7)
      travel 2.days
      q.extend_by!(user: user, days: 30, note: "still flaky")

      expect(q.reload.expires_at).to eq(Time.current + 30.days)
      expect(q.events.order(:id).last).to have_attributes(action: "extended", actor: user, note: "still flaky",
                                                          expires_at: Time.current + 30.days)
    end

    it "refuses an inactive quarantine and a bad duration without writing an event" do
      q = quarantine!(days: 7)
      expect { q.extend_by!(user: user, days: 45) }.to raise_error(ActiveRecord::RecordInvalid, /Duration/)
      travel 8.days
      expect { q.extend_by!(user: user, days: 7) }.to raise_error(described_class::Inactive)
      expect(q.events.count).to eq(1)
    end
  end

  describe "#release!" do
    it "sets released_at and released_by, never deletes, and records the note" do
      q = quarantine!
      q.release!(user: user, note: "fixed in #42")

      expect(q.reload).to have_attributes(released_at: now, released_by: user)
      expect(described_class.exists?(q.id)).to be(true)
      expect(q.events.order(:id).pluck(:action, :note)).to eq([ [ "quarantined", nil ], [ "released", "fixed in #42" ] ])
      expect { q.release!(user: user) }.to raise_error(described_class::Inactive)
    end

    it "rejects a note over 500 characters and keeps the quarantine active" do
      q = quarantine!
      expect { q.release!(user: user, note: "x" * 501) }.to raise_error(ActiveRecord::RecordInvalid, /Note is too long/)
      expect(q.reload).to be_active
    end
  end

  describe "deletion" do
    it "goes with its test case, also through retention's delete_all, and with its project" do
      q = quarantine!
      TestCase.where(id: test_case.id).delete_all
      expect(described_class.exists?(q.id)).to be(false)
      expect(QuarantineEvent.where(quarantine_id: q.id)).to be_empty

      other = quarantine!(target: create(:test_case, project: project))
      project.destroy!
      expect(described_class.exists?(other.id)).to be(false)
      expect(QuarantineEvent.count).to eq(0)
    end
  end
end
