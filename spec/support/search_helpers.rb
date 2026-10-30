module SearchHelpers
  # One stored result in its own run. Create results oldest first: "latest" is the highest id.
  def search_result(test_case, status:, branch: "main", at: 1.day.ago, tags: [], message: nil, exception: nil, duration: 100)
    run = create(:run, project: test_case.project, branch: branch, created_at: at)
    TestResult.create!(run: run, test_case: test_case, identifier: SecureRandom.hex(4), status: status, duration_ms: duration,
                       tags: tags, tags_text: TestResult.tags_text_for(tags), failure_message: message, exception_class: exception)
  end
end

RSpec.configure { |c| c.include SearchHelpers }
