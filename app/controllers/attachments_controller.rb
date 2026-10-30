# Test-result attachments, served only to members of the result's project.
# Only the INLINE_TYPES allowlist displays inline; everything else downloads.
# On Disk the app streams the file itself: Active Storage forces HTML and SVG to
# application/octet-stream, and the per-controller CSP below sandboxes whatever
# is served, so an uploaded file can never run script on this origin. In object
# storage (R2) the member is redirected to a short-lived presigned URL on the
# bucket's own origin, signed with the same type and disposition.
class AttachmentsController < ApplicationController
  include ActiveStorage::Streaming

  INLINE_TYPES = %w[image/png image/jpeg image/gif image/webp video/mp4 video/webm].freeze
  SIGNED_URL_LIFETIME = 5.minutes

  content_security_policy do |policy|
    policy.directives.clear # start from nothing, not the app-wide policy
    policy.default_src :none
    policy.sandbox
  end
  # Enforced in every environment, unlike the app-wide policy.
  content_security_policy_report_only false

  def show
    attachment = ActiveStorage::Attachment.find(params[:id])
    raise ActiveRecord::RecordNotFound unless viewable?(attachment)

    blob = attachment.blob
    disposition = inline?(blob) ? "inline" : "attachment"
    return redirect_to_storage(blob, disposition) unless disk_service?(blob.service)

    response.headers["Cache-Control"] = "private, max-age=300"
    response.headers["X-Content-Type-Options"] = "nosniff"
    if request.headers["Range"].present?
      send_blob_byte_range_data(blob, request.headers["Range"], disposition: disposition)
    else
      send_blob_stream(blob, disposition: disposition)
    end
  end

  private

  # Active Storage loads DiskService only when a Disk service is configured, so guard the constant.
  def disk_service?(service)
    defined?(ActiveStorage::Service::DiskService) && service.is_a?(ActiveStorage::Service::DiskService)
  end

  # Blob#url signs content_type_for_serving and forces HTML and SVG to download.
  def redirect_to_storage(blob, disposition)
    response.headers["Cache-Control"] = "private, no-store"
    redirect_to blob.url(expires_in: SIGNED_URL_LIFETIME, disposition: disposition), allow_other_host: true
  end

  def viewable?(attachment)
    attachment.record_type == "TestResult" &&
      TestResult.joins(:run)
                .where(id: attachment.record_id, runs: { project_id: Current.user.projects.select(:id) })
                .exists?
  end

  def inline?(blob)
    INLINE_TYPES.include?(blob.content_type) && params[:disposition] != "attachment"
  end
end
