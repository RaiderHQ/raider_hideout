module Builds
  # Identifies one GitHub Actions workflow run across its re-run attempts.
  # Every parsing path is total: odd or hostile input yields nil / 1, never raises.
  module RunKey
    PROVIDER = "github_actions".freeze
    BUILD_KEY = %r{\Agithub_actions:([^:\s/]+/[^:\s/]+):(\d{1,20}):(\d{1,10})\z}
    REPOSITORY = %r{\A[^:\s/]+/[^:\s/]+\z}
    RUN_ID = /\A\d{1,20}\z/
    MAX_ATTEMPT = 2_147_483_647

    module_function

    def from_ci(ci)
      return nil unless ci.is_a?(Hash) && ci["provider"] == PROVIDER

      repository = ci["repository"]
      build_id = ci["build_id"]
      if repository.is_a?(String) && build_id.is_a?(String) && repository.match?(REPOSITORY) && build_id.match?(RUN_ID)
        return "#{PROVIDER}:#{repository}:#{build_id}"
      end

      from_build_key(ci["build_key"])&.first
    end

    def from_build_key(build_key)
      return nil unless build_key.is_a?(String)

      match = BUILD_KEY.match(build_key)
      return nil unless match

      [ "#{PROVIDER}:#{match[1]}:#{match[2]}", attempt(match[3]) ]
    end

    MAX_KEY_LENGTH = 512

    # Project-scoped lookup for the API: [build, requested attempt] or nil. Never raises.
    def find_build(project, build_key)
      return nil unless build_key.is_a?(String) && build_key.length <= MAX_KEY_LENGTH

      parsed = from_build_key(build_key)
      exact = project.builds.find_by(build_key: build_key)
      return [ exact, parsed ? parsed.last : 1 ] if exact
      return nil unless parsed

      merged = project.builds.find_by(ci_run_key: parsed.first)
      merged && [ merged, parsed.last ]
    end

    def attempt(value)
      number = Integer(value.to_s, 10)
      number.between?(1, MAX_ATTEMPT) ? number : 1
    rescue ArgumentError, TypeError
      1
    end
  end
end
