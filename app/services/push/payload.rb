module Push
  # The notification the phone shows: title, one body line, and the page to open. Nothing
  # beyond the first failed test's name leaves the server (it passes through the push service).
  module Payload
    MAX_BYTES = 3_000
    NAME_LENGTH = 300
    LABEL_LENGTH = 100

    def self.for(build, events, attempt: 1)
      project = build.project
      first_failed = build.effective_results.where(status: "failed").includes(:test_case).order(:id).first
      payload = {
        title: title(build, project, events, attempt),
        body: body(build, first_failed&.test_case&.full_name, NAME_LENGTH),
        path: path(project, build, first_failed)
      }
      shrink(payload, build, first_failed&.test_case&.full_name)
    end

    def self.title(build, project, events, attempt)
      headline = if events.include?("rerun_result")
        build.status == "failed" ? "build failed" : "build passed"
      elsif events.include?("gate_failed") && !events.include?("failed")
        "quality gate failed"
      else
        Notifications::Message.headline_for(build, events)
      end
      headline = "Re-run (attempt #{attempt}): #{headline}" if build.rerun_attempt?(attempt)
      "Raider: #{headline} — #{project.name.to_s.truncate(LABEL_LENGTH)}"
    end

    def self.body(build, name, name_length)
      line = "#{build.branch.to_s.truncate(LABEL_LENGTH)} · #{build.failed_count} failed"
      name.present? ? "#{line}\n#{name.truncate(name_length)}" : line
    end

    def self.path(project, build, first_failed)
      helpers = Rails.application.routes.url_helpers
      return helpers.project_build_path(project, build) unless first_failed

      helpers.project_build_path(project, build, result: first_failed.id, anchor: ActionView::RecordIdentifier.dom_id(first_failed))
    end

    # Multibyte or escaped characters can push the JSON past the cap; halve the name until it fits.
    def self.shrink(payload, build, name)
      length = NAME_LENGTH
      while payload.to_json.bytesize >= MAX_BYTES && length > 1
        length /= 2
        payload = payload.merge(body: body(build, name, length))
      end
      payload
    end
  end
end
