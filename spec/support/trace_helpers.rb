# Attaches a trace zip the way Ingest does: declared type kept, never re-identified.
module TraceHelpers
  def attach_trace(result, io:, filename: "trace.zip")
    result.attachments.attach(io: io, filename: filename, content_type: Ingest::TRACE_CONTENT_TYPE, identify: false)
    result.attachments.last
  end
end

RSpec.configure do |c|
  c.include TraceHelpers, type: :request
  c.include TraceHelpers, type: :system
  c.include TraceHelpers, type: :view
end
