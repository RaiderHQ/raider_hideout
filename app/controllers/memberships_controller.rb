class MembershipsController < ApplicationController
  before_action :set_organization
  before_action :set_membership, only: %i[update destroy]

  def index
    @memberships = @organization.memberships.includes(:user).order(:created_at, :id)
    @invitations = @organization.invitations.outstanding.order(:created_at, :id) if role_at_least?(:admin)
  end

  def update
    Organizations::MembershipChange.update_role!(actor: Current.user, membership: @membership, role: params.dig(:membership, :role))
    redirect_to organization_memberships_path(@organization), notice: "Role updated."
  rescue Organizations::MembershipChange::Forbidden => e
    forbid(e.required_role)
  rescue Organizations::MembershipChange::Invalid => e
    redirect_to organization_memberships_path(@organization), alert: e.message
  end

  def destroy
    leaving = @membership.user_id == Current.user.id
    Organizations::MembershipChange.remove!(actor: Current.user, membership: @membership)
    if leaving
      redirect_to organizations_path, notice: "You left #{@organization.name}."
    else
      redirect_to organization_memberships_path(@organization), notice: "Member removed."
    end
  rescue Organizations::MembershipChange::Forbidden => e
    forbid(e.required_role)
  rescue Organizations::MembershipChange::Invalid => e
    redirect_to organization_memberships_path(@organization), alert: e.message
  end

  private

  # Nested under organizations, so authorization follows the organization.
  def authorization_organization
    current_organization
  end

  def set_organization
    @organization = current_organization
  end

  def set_membership
    @membership = @organization.memberships.find(params[:id])
  end

  def forbid(required_role)
    @required_role = required_role
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden }
      format.any { head :forbidden }
    end
  end
end
