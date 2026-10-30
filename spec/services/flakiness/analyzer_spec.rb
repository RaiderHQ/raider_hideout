require "rails_helper"

RSpec.describe Flakiness::Analyzer do
  def samples(spec)
    # spec: "P:a F:a P:b R:c S" → status:commit; R = passed after retry; S = skipped
    spec.split.map do |token|
      code, sha = token.split(":")
      status = { "P" => "passed", "F" => "failed", "R" => "passed", "S" => "skipped", "X" => "pending", "Q" => "quarantined" }.fetch(code)
      Flakiness::Sample.new(status: status, commit_sha: sha, retried_flaky: code == "R")
    end
  end

  [
    [ "stable passes",                       "P:a P:b P:c P:d P:e P:f",       false, nil,           0.0 ],
    [ "fewer than 5 samples with flips",     "P:a F:b P:c F:d",               false, nil,           1.0 ],
    [ "flips at threshold",                  "P:a P:b P:c P:d P:e P:f F:g",   false, nil,           0.1667 ],
    [ "flips above threshold",               "P:a F:b P:c P:d P:e P:f",       true,  "flips",       0.4 ],
    [ "genuine break stays failing",         "P:a P:b P:c F:d F:e F:f",       false, nil,           0.2 ],
    [ "same commit pass and fail",           "P:a F:a",                       true,  "same_commit", 1.0 ],
    [ "retry pass",                          "P:a R:b P:c",                   true,  "retry",       0.0 ],
    [ "same commit beats retry",             "R:a F:a",                       true,  "same_commit", 1.0 ],
    [ "skipped and pending ignored",         "P:a S X P:b S P:c P:d P:e",     false, nil,           0.0 ],
    [ "nil commit never matches",            "P F",                           false, nil,           1.0 ],
    [ "quarantined counts as failed on one commit", "P:a Q:a",                     true,  "same_commit", 1.0 ],
    [ "quarantined flips count as failures",       "P:a Q:b P:c Q:d P:e Q:f",     true,  "flips",       1.0 ],
    [ "quarantined after failed on one commit",    "F:a Q:a",                     false, nil,           0.0 ],
    [ "only failed and quarantined never flip",    "F Q F Q F Q",                 false, nil,           0.0 ],
    [ "quarantined joins failed beside a pass",    "P:a F:a Q:a",                 true,  "same_commit", 0.5 ],
    [ "empty history",                       "",                              false, nil,           0.0 ]
  ].each do |label, history, flaky, reason, flip_rate|
    it label do
      verdict = described_class.call(samples(history))
      expect([ verdict.flaky, verdict.reason ]).to eq([ flaky, reason ])
      expect(verdict.flip_rate).to be_within(0.0001).of(flip_rate)
    end
  end
end
