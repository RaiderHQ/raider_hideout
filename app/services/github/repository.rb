module Github
  # Owner, repo and run id from a build's ci_run_key (`github_actions:<owner>/<repo>:<run_id>`),
  # re-checked so nothing but safe path segments ever reaches a request.
  module Repository
    PART = /\A[A-Za-z0-9_.-]{1,100}\z/
    RUN_ID = /\A\d{1,20}\z/
    KEY = %r{\Agithub_actions:([^:/]*)/([^:/]*):([^:/]*)\z}

    module_function

    def valid_part?(value)
      value.is_a?(String) && PART.match?(value) && value != "." && value != ".."
    end

    def from_build(build)
      key = build&.ci_run_key
      return nil unless key.is_a?(String)

      match = KEY.match(key)
      return nil unless match

      owner, repo, run_id = match.captures
      return nil unless valid_part?(owner) && valid_part?(repo) && RUN_ID.match?(run_id)

      [ owner, repo, run_id ]
    end
  end
end
