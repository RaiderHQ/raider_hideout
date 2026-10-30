module StackTraceHelper
  FRAME_PATTERN = /\A((?:[A-Za-z]:)?[^:]+):(\d+)(?::in .*)?\z/
  NON_PROJECT_PREFIXES = %w[vendor/ .bundle/ <internal: ( -].freeze

  LINE_TERMINATORS = /[\n\r\u2028\u2029]/

  def parse_frame(str)
    text = str.to_s.delete_suffix("\r")
    return if text.match?(LINE_TERMINATORS)

    match = FRAME_PATTERN.match(text)
    match && { file: match[1], line: match[2].to_i }
  end

  def project_frame?(line, app_frame)
    frame = parse_frame(line)
    return false unless frame

    app = parse_frame(app_frame)
    return true if app && frame[:file] == app[:file]

    file = frame[:file]
    !file.start_with?("/") && !file.match?(/\A[A-Za-z]:/) &&
      NON_PROJECT_PREFIXES.none? { |prefix| file.start_with?(prefix) } && !file.include?("/gems/")
  end

  def fold_frames(lines, app_frame)
    Array(lines).each_with_object([]) do |line, segments|
      if project_frame?(line, app_frame)
        segments << { kind: :project, text: line }
      elsif segments.last&.dig(:kind) == :folded
        segments.last[:lines] << line
      else
        segments << { kind: :folded, lines: [ line ] }
      end
    end
  end

  def failure_location(app_frame)
    frame = parse_frame(app_frame)
    frame && "#{frame[:file]}:#{frame[:line]}"
  end
end
