class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Raider Hideout <no-reply@localhost>")
  layout "mailer"
end
