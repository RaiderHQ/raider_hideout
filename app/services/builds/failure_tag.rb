module Builds
  # Tag for a failed test, by priority: own-branch flaky, default-branch flaky,
  # new, still failing. Returns [label, kind] or nil.
  module FailureTag
    def self.for(test_case_id, comparison, verdicts, default_branch)
      verdict = verdicts[test_case_id]
      if verdict&.flaky
        return [ "Flaky", :flaky ] if verdict.source == :branch
        return [ "Flaky on #{default_branch}", :flaky ] if verdict.source == :default_branch
      end
      case comparison&.status_for(test_case_id)
      when :new_failure then [ "New", :new ]
      when :still_failing then [ "Still failing", :still_failing ]
      end
    end
  end
end
