module BuildsHelper
  CI_PROVIDER_LABELS = { "github_actions" => "GitHub Actions", "azure_pipelines" => "Azure Pipelines" }.freeze

  def pull_request_url(build)
    return build.pr_url if build.pr_url.to_s.match?(%r{\Ahttps?://}i)
    return nil unless build.provider == "github_actions"
    return nil unless build.pr_number.present? && build.repository.present?
    return nil unless build.repository.match?(/\A[\w.-]+\/[\w.-]+\z/)

    owner, repo = build.repository.split("/")
    return nil if owner.match?(/\A\.+\z/) || repo.match?(/\A\.+\z/)

    "https://github.com/#{build.repository}/pull/#{build.pr_number}"
  end

  def ci_provider_label(build)
    CI_PROVIDER_LABELS.fetch(build.provider.to_s) { build.provider.presence || "CI" }
  end
end
