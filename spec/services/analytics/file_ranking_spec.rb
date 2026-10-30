require "rails_helper"

RSpec.describe Analytics::FileRanking do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-28 12:00:00") }
  let(:project) { create(:project) }

  around { |example| travel_to(now) { example.run } }

  def tc(name, file:) = create(:test_case, project: project, full_name: name, file_path: file)

  def rows(query = "", limit: 10) = described_class.new(project, analytics_filter(query, project: project)).rows(limit: limit)

  it "groups executed results by file with distinct tests, failures, floored rate and total time" do
    login = tc("Login works", file: "spec/login_spec.rb")
    logout = tc("Logout works", file: "spec/login_spec.rb")
    search_result(login, status: "failed", duration: 100)
    search_result(login, status: "passed", duration: 200)
    search_result(logout, status: "quarantined", duration: 300)
    search_result(logout, status: "skipped", duration: 5_000)

    expect(rows.sole.to_h).to eq(file_path: "spec/login_spec.rb", tests: 2, executed: 3, failures: 2, failure_rate: 66,
                                 total_duration_ms: 600)
  end

  it "orders by failures, then exact failure rate, then path, and keeps files with no failures" do
    search_result(tc("A", file: "spec/b_spec.rb"), status: "failed")              # 1 of 1
    b = tc("B", file: "spec/c_spec.rb")
    2.times { search_result(b, status: "passed") }                               # 0 of 2
    search_result(tc("C", file: "spec/a_spec.rb"), status: "passed")              # 0 of 1
    d = tc("D", file: "spec/d_spec.rb")
    search_result(d, status: "failed")
    search_result(d, status: "passed")                                           # 1 of 2
    search_result(tc("E", file: "spec/e_spec.rb"), status: "pending")             # never executed

    expect(rows.map(&:file_path)).to eq(%w[spec/b_spec.rb spec/d_spec.rb spec/a_spec.rb spec/c_spec.rb])
  end

  it "follows branch:, tag: and file:" do
    test = tc("Login works", file: "spec/login_spec.rb")
    search_result(test, status: "failed", tags: [ "smoke" ])
    search_result(test, status: "failed", branch: "feature/x")
    search_result(tc("Cart", file: "spec/cart_spec.rb"), status: "failed")

    expect(rows.map(&:file_path)).to eq(%w[spec/cart_spec.rb spec/login_spec.rb])
    expect(rows("tag:smoke").sole.failures).to eq(1)
    expect(rows("branch:feature/x").sole.file_path).to eq("spec/login_spec.rb")
    expect(rows("file:cart").sole.file_path).to eq("spec/cart_spec.rb")
  end
end
