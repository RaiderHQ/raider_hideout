# Fallback page the service worker serves when a navigation fails offline.
class OfflineController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_access
  # The worker caches this page at install time; a redirect to /setup would be cached instead.
  skip_before_action :redirect_to_setup

  layout false

  def show
  end
end
