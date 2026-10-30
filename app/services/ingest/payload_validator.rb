class Ingest
  class PayloadValidator
    SUPPORTED_VERSIONS = [ 1, 2 ].freeze
    STATUSES = %w[passed failed pending skipped].freeze
    # Version 2 only adds quarantined (spec §5.1).
    STATUSES_BY_VERSION = { 1 => STATUSES, 2 => (STATUSES + %w[quarantined]).freeze }.freeze
    REQUIRED_STRINGS = %w[identifier full_name file_path].freeze
    INTEGER_FIELDS = %w[duration_ms attempts line_number].freeze
    MAX_INT = 2_147_483_647
    MAX_STRING = 255

    def initialize(data, part_names)
      @data = data
      @part_names = part_names
    end

    def errors
      return [ "payload must be a JSON object" ] unless @data.is_a?(Hash)

      version = @data["schema_version"]
      unless SUPPORTED_VERSIONS.include?(version)
        return [ "unsupported schema_version #{version.inspect}; supported: #{SUPPORTED_VERSIONS.join(', ')}" ]
      end

      @statuses = STATUSES_BY_VERSION.fetch(version.to_i)

      errors = []
      errors << "client_run_id is required" unless present_string?(@data["client_run_id"])
      run_errors(errors)
      results_errors(errors)
      errors
    end

    private

    def run_errors(errors)
      run = @data["run"]
      return errors << "run must be an object" unless run.is_a?(Hash)

      %w[started_at finished_at].each do |key|
        errors << "run.#{key} is not an ISO 8601 time" if run[key].present? && !iso_time?(run[key])
      end
      %w[ci git environment].each do |key|
        errors << "run.#{key} must be an object" if run.key?(key) && !run[key].nil? && !run[key].is_a?(Hash)
      end
      %w[ci git].each do |key|
        next unless run[key].is_a?(Hash)

        run[key].each do |field, value|
          next if key == "git" && field == "pr"

          errors << "run.#{key}.#{field} must be a string" unless value.nil? || value.is_a?(String)
        end
      end
      length_errors(errors, run.dig("ci", "build_key"), "run.ci.build_key") if run["ci"].is_a?(Hash)
      pr_errors(errors, run["git"]["pr"]) if run["git"].is_a?(Hash)
      shard_errors(errors, run["shard"])
    end

    def pr_errors(errors, pr)
      return if pr.nil?
      return errors << "run.git.pr must be an object" unless pr.is_a?(Hash)

      pr["number"].nil? ? errors << "run.git.pr.number must be an integer" : integer_errors(errors, pr["number"], "run.git.pr.number", min: 1)
      %w[base_branch head_branch head_sha].each do |key|
        errors << "run.git.pr.#{key} must be a string" unless pr[key].is_a?(String)
      end
    end

    def shard_errors(errors, shard)
      return if shard.nil?
      return errors << "run.shard must be an object" unless shard.is_a?(Hash)

      index = shard["index"]
      index.is_a?(Integer) ? range_errors(errors, index, "run.shard.index", 1) : errors << "run.shard.index must be an integer"
      integer_errors(errors, shard["total"], "run.shard.total", min: 1)
      label = shard["label"]
      return errors << "run.shard.label must be a string" unless label.is_a?(String)

      length_errors(errors, label, "run.shard.label")
    end

    def length_errors(errors, value, label)
      errors << "#{label} is too long (maximum #{MAX_STRING} characters)" if value.is_a?(String) && value.length > MAX_STRING
    end

    def results_errors(errors)
      results = @data["results"]
      return errors << "results must be an array" unless results.is_a?(Array)

      results.each_with_index do |result, i|
        next errors << "results[#{i}] must be an object" unless result.is_a?(Hash)

        REQUIRED_STRINGS.each { |key| errors << "results[#{i}].#{key} is required" unless present_string?(result[key]) }
        errors << "results[#{i}].status must be one of #{@statuses.join(', ')}" unless @statuses.include?(result["status"])
        tags = result["tags"]
        errors << "results[#{i}].tags must be an array of strings" unless tags.nil? || (tags.is_a?(Array) && tags.all?(String))
        INTEGER_FIELDS.each { |key| integer_errors(errors, result[key], "results[#{i}].#{key}") }
        failure = result["failure"]
        # failure.app_frame (0.6.0+) is optional; a non-string value is ignored at ingest, not rejected.
        errors << "results[#{i}].failure must be an object" unless failure.nil? || failure.is_a?(Hash)
        attachment_errors(errors, result["attachments"], i)
      end
    end

    def attachment_errors(errors, attachments, i)
      return if attachments.nil?
      return errors << "results[#{i}].attachments must be an array" unless attachments.is_a?(Array)

      attachments.each_with_index do |attachment, j|
        next errors << "results[#{i}].attachments[#{j}] must be an object" unless attachment.is_a?(Hash)
        next if @part_names.include?(attachment["part"])

        errors << "results[#{i}].attachments[#{j}].part #{attachment['part'].inspect} was not uploaded"
      end
    end

    def integer_errors(errors, value, label, min: 0)
      return if value.nil?
      return errors << "#{label} must be an integer" unless value.is_a?(Integer)

      range_errors(errors, value, label, min)
    end

    def range_errors(errors, value, label, min)
      errors << "#{label} is out of range" unless (min..MAX_INT).cover?(value)
    end

    def present_string?(value)
      value.is_a?(String) && value.strip != ""
    end

    def iso_time?(value)
      value.is_a?(String) && Time.iso8601(value)
    rescue ArgumentError
      false
    end
  end
end
