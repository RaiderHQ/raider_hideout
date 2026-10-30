# Turbo stream subscriptions for project pages. Besides the signed stream
# name check of Turbo::StreamsChannel, the subscriber must still belong to
# the project's organization, so a removed member or a leaked signed name
# can't keep receiving live updates.
class ProjectStreamsChannel < Turbo::StreamsChannel
  def subscribed
    stream_name = verified_stream_name_from_params
    if stream_name && member_of?(project_from(stream_name))
      stream_from stream_name
    else
      reject
    end
  end

  private

  # Stream names are "<project gid param>:builds" / ":runs".
  def project_from(stream_name)
    GlobalID::Locator.locate(stream_name.split(":").first, only: Project)
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def member_of?(project)
    project.present? && connection.current_user.projects.exists?(id: project.id)
  end
end
