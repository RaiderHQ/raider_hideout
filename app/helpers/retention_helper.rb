module RetentionHelper
  def results_expiry(runs)
    purged = runs.count { |run| run.results_purged_at.present? }
    return if purged.zero?

    purged == runs.size ? :all : :some
  end

  def results_expired_notice(runs)
    days = Retention.config.result_days
    text = case results_expiry(runs)
    when :all then "Test results expired after #{days} days. Totals are kept."
    when :some then "Some shards' results expired after #{days} days."
    end
    tag.p(text, class: "text-sm text-neutral-mid mb-4", data: { testid: "results-expired" }) if text
  end

  def attachments_expired?(result)
    TestResult::FAILING_STATUSES.include?(result.status) && result.run.attachments_purged_at.present? && result.attachments.none?
  end
end
