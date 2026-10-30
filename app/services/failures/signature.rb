require "digest"

module Failures
  # Spec §4.2: a stable fingerprint of a failure, made from its exception class,
  # its normalized message and the app frame it was raised from.
  module Signature
    Result = Data.define(:exception_class, :normalized_message, :frame, :digest)

    MESSAGE_LIMIT = 200
    CUCUMBER_STEP_SUFFIX = /\([^()\n]+:\d+\)\z/
    # A ' after a word character is an apostrophe ("can't"), not a quote.
    QUOTED = /"[^"\n]*"|(?<!\w)'[^'\n]*'/
    UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/
    HEX = /0x[0-9a-f]+/i
    DIGITS = /\d+/
    LIBRARY_MARKERS = %w[/gems/ /vendor/ /.bundle/ /lib/ruby/].freeze
    APP_ROOTS = %r{/(?=(?:spec|features|app|lib|test)/)}
    ABSOLUTE = %r{\A(/|[A-Za-z]:/)}
    LINE_NUMBER = /(?=:\d+)/
    FRAME_LIMIT = 500
    # "LoginPage#submit" / "Admin::Page.open" -> the method name only.
    OWNER_PREFIX = /\b[A-Z]\w*(?:::[A-Z]\w*)*[#.](?=\S)/
    # The reporter's placeholder for a step it could not name.
    STEP_PLACEHOLDERS = %w[Step].freeze

    module_function

    def for(exception_class:, message:, app_frame:, backtrace:)
      klass = exception_class.to_s.strip.presence || "UnknownError"
      normalized = normalize_message(message)
      source = app_frame.is_a?(String) && app_frame.strip.present? ? slashed(app_frame[0, FRAME_LIMIT]) : fallback_frame(backtrace)
      frame = normalize_frame(source)
      Result.new(exception_class: klass, normalized_message: normalized, frame: frame,
                 digest: Digest::SHA256.hexdigest("#{klass}\0#{normalized}\0#{frame}"))
    end

    def normalize_message(message)
      text = message.to_s
      prefix, rest = text.split("\n\n", 2)
      text = rest if rest && (prefix.rstrip.match?(CUCUMBER_STEP_SUFFIX) || STEP_PLACEHOLDERS.include?(prefix.strip))
      # The first non-blank line: RSpec's `eq` failures start with "\n".
      line = text.lines.map(&:strip).find(&:present?).to_s
      line.gsub(QUOTED, "\"…\"").gsub(UUID, "<uuid>").gsub(HEX, "<hex>").gsub(DIGITS, "<n>")
          .squish[0, MESSAGE_LIMIT]
    end

    # The first app line: not a gem, vendored or stdlib line, and an absolute path
    # only when it has an app root to cut at (so ".../bin/rspec:25" never qualifies).
    def fallback_frame(backtrace)
      lines = Array(backtrace).flat_map { |entry| entry.to_s.split("\n") }.map { |line| slashed(line) }
      lines.find do |line|
        next false if line.empty? || line.start_with?("<internal:")
        next false if LIBRARY_MARKERS.any? { |marker| line.include?(marker) }

        path = line.split(LINE_NUMBER, 2).first
        !path.match?(ABSOLUTE) || path.match?(APP_ROOTS)
      end
    end

    # Windows backslashes become "/" so markers and app roots match.
    def slashed(line)
      line.strip.tr("\\", "/")
    end

    def normalize_frame(line)
      return "" if line.blank?

      path, location = line.strip.split(LINE_NUMBER, 2)
      path = cut_absolute(path).delete_prefix("./")
      "#{path}#{frame_label(location.to_s.sub(/\A:\d+/, ''))}"
    end

    # Ruby 3.3 writes "in `submit'", 3.4 "in 'LoginPage#submit'": both become "in submit".
    def frame_label(label)
      label.delete("`'").gsub(OWNER_PREFIX, "")
    end

    # "/home/runner/work/x/x/spec/pages/a.rb" -> "spec/pages/a.rb", at the last app root.
    def cut_absolute(path)
      return path unless path.match?(ABSOLUTE)

      index = path.rindex(APP_ROOTS)
      index ? path[(index + 1)..] : path
    end
  end
end
