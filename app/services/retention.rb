# Retention settings and purge (spec 2026-10-20 §4.1).
module Retention
  def self.config
    @config ||= Config.from(ENV)
  end
end
