module Notifications
  Message = Data.define(:title, :headline, :summary, :project_name, :branch, :commit,
                        :failures, :new_flaky, :pass_rate, :build_url, :pr_url)

  class Message
    MAX_LISTED = 5
    COMMIT_LENGTH = 80
    ITEM_LENGTH = 200

    def self.for_build(build, events, url_options:)
      project = build.project
      headline = headline_for(build, events)
      new(
        title: "Raider: #{headline} — #{project.name}",
        headline: headline,
        summary: "#{build.failed_count} failed, #{build.passed_count} passed, " \
                 "#{build.skipped_count} skipped (#{build.duration_label})",
        project_name: project.name,
        branch: build.branch,
        commit: commit_label(build),
        failures: failures_for(build),
        new_flaky: new_flaky_for(build),
        pass_rate: build.pass_rate,
        build_url: Rails.application.routes.url_helpers.project_build_url(project, build, **url_options),
        pr_url: ApplicationController.helpers.pull_request_url(build)
      )
    end

    def self.test(channel, url_options:)
      project = channel.project
      new(
        title: "Raider: test notification — #{project.name}",
        headline: "test notification",
        summary: "This is a test notification from Raider.",
        project_name: project.name,
        branch: nil, commit: nil, failures: [], new_flaky: [], pass_rate: nil,
        build_url: Rails.application.routes.url_helpers.project_url(project, **url_options),
        pr_url: nil
      )
    end

    def self.headline_for(build, events)
      if events.include?("failed") then "build failed"
      elsif events.include?("recovered") then "build recovered"
      elsif events.include?("low_pass_rate") then "pass rate #{build.pass_rate}%"
      else "new flaky tests"
      end
    end

    def self.commit_label(build)
      return nil if build.commit_sha.blank?

      first_line = build.commit_message.to_s.lines.first.to_s.strip
      "#{build.commit_sha[0, 7]} #{first_line}".strip.truncate(COMMIT_LENGTH, omission: "")
    end

    def self.failures_for(build)
      scope = TestResult.where(run_id: build.runs.select(:id), status: "failed")
      total = scope.count
      lines = scope.includes(:test_case).order(:id).limit(MAX_LISTED).map do |result|
        "#{result.test_case.full_name} (#{result.test_case.file_path})".truncate(ITEM_LENGTH)
      end
      lines << "and #{total - MAX_LISTED} more" if total > MAX_LISTED
      lines
    end

    def self.new_flaky_for(build)
      TestCase.where(id: Rules.new_flaky_scope(build).select(:test_case_id))
              .order(:file_path, :full_name).limit(MAX_LISTED).pluck(:full_name).map { |n| n.truncate(ITEM_LENGTH) }
    end
  end
end
