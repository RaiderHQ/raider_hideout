# Fallback page the service worker serves when a navigation fails offline.
class OfflineController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_access

  layout false

  def show
  end
end
