class NotificationMailer < ApplicationMailer
  def build_notification(channel, message)
    @message = message
    subject = if message.branch.present?
      "[Raider Hideout] #{message.project_name}: #{message.headline} on #{message.branch}"
    else
      "[Raider Hideout] #{message.project_name}: #{message.headline}"
    end
    mail(to: recipients(channel), subject: subject.gsub(/\s+/, " "))
  end

  private

  def recipients(channel)
    list = channel.recipient_list
    list += channel.project.organization.notification_recipients if channel.include_owner
    list.uniq
  end
end
