module ComparisonHelper
  LIST_LIMIT = 50
  TAG_STYLES = {
    flaky: "text-accent-gold bg-accent-gold-bg",
    new: "text-status-err bg-status-err-bg",
    still_failing: "text-neutral-mid bg-neutral-lt"
  }.freeze
  BUCKET_LABELS = {
    new_failures: "New failures", still_failing: "Still failing", fixed: "Fixed", new_tests: "New tests"
  }.freeze

  def failure_tag(test_case_id, comparison, verdicts, default_branch)
    Builds::FailureTag.for(test_case_id, comparison, verdicts, default_branch)
  end

  def failure_tag_pill(tag)
    label, kind = tag
    content_tag(:span, label, data: { testid: "failure-tag" },
                              class: "#{UiHelper::PILL_BASE} #{TAG_STYLES.fetch(kind)}")
  end
end
