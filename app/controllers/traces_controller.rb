# Raider trace viewer support. The zip is streamed as an opaque download; it is never unzipped
# on the server. The CSP is the sandbox policy AttachmentsController uses.
class TracesController < ApplicationController
  include ActiveStorage::Streaming

  content_security_policy(only: :zip) do |policy|
    policy.directives.clear
    policy.default_src :none
    policy.sandbox
  end
  content_security_policy_report_only false, only: :zip

  def zip
    blob = find_trace!.blob
    send_blob_stream(blob, disposition: "attachment")
    response.headers["Content-Type"] = "application/octet-stream"
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  private

  # 404 unless the attachment is a trace of this result, in a project the user belongs to.
  def find_trace!
    attachment = ActiveStorage::Attachment.includes(:blob).find(params[:id])
    valid = attachment.record_type == "TestResult" &&
            attachment.record_id == params[:test_result_id].to_i &&
            attachment.blob.content_type == Ingest::TRACE_CONTENT_TYPE &&
            TestResult.visible_to(Current.user).where(id: attachment.record_id).exists?
    raise ActiveRecord::RecordNotFound unless valid

    attachment
  end
end
