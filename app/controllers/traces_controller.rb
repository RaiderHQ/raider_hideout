# Raider trace viewer support. The zip is streamed as an opaque download; it is never unzipped
# on the server. The CSP is the sandbox policy AttachmentsController uses.
class TracesController < ApplicationController
  include ActiveStorage::Streaming

  content_security_policy(only: :zip) do |policy|
    policy.directives.clear
    policy.default_src :none
    policy.sandbox
  end
  # The viewer renders snapshot CSS from a sandboxed iframe's parent page, so it needs inline styles. The
  # nonce stays on script-src only: a style nonce would make browsers ignore 'unsafe-inline'.
  content_security_policy(only: :show) { |policy| policy.style_src :self, :unsafe_inline }
  content_security_policy_report_only false
  before_action -> { request.content_security_policy_nonce_directives = %w[script-src] }, only: :show

  def show
    @trace = find_trace!
    @result = @trace.record
  end

  # Headers are fixed before the first write: ActionController::Live commits them then.
  def zip
    blob = find_trace!.blob
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_stream(filename: blob.filename.sanitized, disposition: "attachment", type: "application/octet-stream") do |stream|
      blob.download { |chunk| stream.write chunk }
    end
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
