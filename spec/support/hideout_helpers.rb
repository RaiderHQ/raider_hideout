# Instance settings in specs (plan 2026-10-29).
module HideoutHelpers
  def with_env(values)
    stub_const("ENV", ENV.to_h.merge(values))
  end

  def open_signup! = with_env("HIDEOUT_OPEN_SIGNUP" => "true")

  def mail_disabled!
    allow(Hideout).to receive(:mail_enabled?).and_return(false)
  end
end

RSpec.configure { |c| c.include HideoutHelpers }
