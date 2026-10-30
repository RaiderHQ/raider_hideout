# Nightly (config/recurring.yml): records an "expired" event for quarantines that ran
# out. Quarantines stop applying at expires_at whether or not this ran (spec §5.2).
class ExpireQuarantinesJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Quarantine.where(released_at: nil).where(Quarantine.arel_table[:expires_at].lteq(now))
              .where.not(id: QuarantineEvent.where(action: "expired").select(:quarantine_id))
              .find_each do |quarantine|
      quarantine.events.create!(action: "expired", actor: nil, expires_at: quarantine.expires_at)
    end
  end
end
