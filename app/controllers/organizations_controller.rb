class OrganizationsController < ApplicationController
  before_action :set_organization, only: %i[show edit update destroy]

  def index
    @organizations = sorted(Current.user.organizations)
    @memberships = Current.user.memberships.index_by(&:organization_id)
  end

  def show
    @projects = @organization.projects.order(:name)
  end

  def new
    @organization = Organization.new
  end

  def create
    @organization = Organization.new(organization_params)
    saved = Organization.transaction do
      @organization.save && @organization.memberships.create!(user: Current.user, role: "owner")
    end
    if saved
      redirect_to organization_path(@organization), notice: "Organization created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    require_role!(:owner)
  end

  def update
    require_role!(:owner)
    return if performed?

    if @organization.update(organization_params)
      redirect_to organization_path(@organization), notice: "Organization renamed."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    require_role!(:owner)
    return if performed?

    if @organization.personal?
      return render(html: helpers.tag.p("Your personal organization can't be deleted.", class: "text-neutral-dk"), layout: true, status: :forbidden)
    end
    unless params[:confirm_name] == @organization.name
      @delete_error = "Type the organization name to confirm deletion"
      return render(:edit, status: :unprocessable_content)
    end

    @organization.destroy!
    personal = Current.user.personal_organization
    redirect_to (personal ? organization_path(personal) : organizations_path), notice: "Organization deleted."
  end

  private

  def authorization_organization
    current_organization
  end

  def set_organization
    @organization = current_organization
  end

  def organization_params
    params.expect(organization: [ :name ])
  end

  def sorted(organizations)
    organizations.sort_by { |o| [ o.personal ? 0 : 1, o.name.downcase ] }
  end
end
