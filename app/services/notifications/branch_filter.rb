module Notifications
  module BranchFilter
    DEFAULT_BRANCHES = %w[main master].freeze

    def self.match?(channel, build)
      case channel.branch_filter
      when "all" then true
      when "default" then default_match?(build)
      when "pattern" then pattern_match?(channel.branch_pattern, build.branch)
      else false
      end
    end

    def self.default_match?(build)
      return false if build.branch.blank?

      defaults = build.default_branch.presence ? [ build.default_branch ] : DEFAULT_BRANCHES
      defaults.include?(build.branch)
    end

    def self.pattern_match?(pattern, branch)
      return false if branch.blank? || pattern.blank?

      File.fnmatch?(pattern, branch, File::FNM_PATHNAME)
    end
  end
end
