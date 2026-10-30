module ApplicationHelper
  # The signed-in user's organizations: personal first, then alphabetical.
  def menu_organizations
    Current.user.organizations.sort_by { |o| [ o.personal ? 0 : 1, o.name.downcase ] }
  end
end
