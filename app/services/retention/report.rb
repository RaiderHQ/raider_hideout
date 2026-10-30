module Retention
  Report = Struct.new(:runs, :results, :attachments, :error_groups, :test_cases, keyword_init: true) do
    def self.zero
      new(runs: 0, results: 0, attachments: 0, error_groups: 0, test_cases: 0)
    end

    def to_s
      to_h.map { |key, value| "#{key}=#{value}" }.join(" ")
    end
  end
end
