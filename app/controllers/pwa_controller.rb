# Manifest and service worker, reachable signed out. Rails::PwaController is
# not an ApplicationController, so it skips authentication by design.
class PwaController < Rails::PwaController
  # The browser must revalidate the worker script on every update check.
  after_action -> { response.headers["Cache-Control"] = "no-cache" }, only: :service_worker
end
