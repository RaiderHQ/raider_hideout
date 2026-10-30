require "json_schemer"

# Every API request spec validates what it got against docs/openapi.yaml (spec §9).
module OpenApiHelpers
  def self.document
    @document ||= YAML.safe_load_file(Rails.root.join("docs/openapi.yaml"))
  end

  def self.openapi
    @openapi ||= JSONSchemer.openapi(document)
  end

  # The documented path template matching a request path; literal segments beat parameters.
  def self.template_for(path)
    matches = document.fetch("paths").keys.select { |template| path.match?(regex(template)) }
    raise "docs/openapi.yaml documents no path matching #{path}" if matches.empty?

    matches.min_by { |template| template.count("{") }
  end

  def self.regex(template)
    /\A#{Regexp.escape(template).gsub(/\\\{\w+\\\}/, "[^/]+")}\z/
  end

  # A path template as a JSON Pointer segment in a URI fragment: json_schemer raises on raw braces.
  def self.pointer_escape(template)
    template.gsub("~", "~0").gsub("/", "~1").gsub("{", "%7B").gsub("}", "%7D")
  end

  def expect_documented_response
    template = OpenApiHelpers.template_for(request.path)
    verb = request.request_method.downcase
    status = response.status.to_s
    entry = OpenApiHelpers.document.dig("paths", template, verb, "responses", status)
    expect(entry).to be_present, "docs/openapi.yaml documents no #{status} for #{verb.upcase} #{template}"

    base = entry["$ref"] || "#/paths/#{OpenApiHelpers.pointer_escape(template)}/#{verb}/responses/#{status}"
    schema = OpenApiHelpers.openapi.ref("#{base}/content/application~1json/schema")
    errors = schema.validate(response.parsed_body).map { |error| error["error"] }
    expect(errors).to be_empty, "#{verb.upcase} #{request.path} (#{status}) does not match docs/openapi.yaml:\n#{errors.join("\n")}"
  end
end

RSpec.configure { |config| config.include OpenApiHelpers, type: :request }
