module QuarantinesHelper
  def quarantine_date(time) = time.strftime("%B %-d, %Y")

  def quarantine_actor(user) = user&.email_address || "a former member"

  def quarantine_event_actor(event)
    return "Raider" if event.action == "expired"

    quarantine_actor(event.actor)
  end

  def quarantine_duration_options = Quarantine::DURATIONS.map { |days| [ "#{days} days", days ] }
end
