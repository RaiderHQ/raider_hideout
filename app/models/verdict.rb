# A test's flaky verdict as seen from one branch. `source` says where it came from:
# :branch (the branch's own well-sampled row), :default_branch (the fallback) or :none.
Verdict = Data.define(:flaky, :reason, :flip_rate, :source)
Verdict::NONE = Verdict.new(flaky: false, reason: nil, flip_rate: nil, source: :none)
