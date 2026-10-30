require "production_checks"

# SECRET_KEY_BASE_DUMMY is set during assets:precompile in the Dockerfile,
# which boots production without the runtime environment.
ProductionChecks.verify!(ENV) if ProductionChecks.enabled?(ENV)
