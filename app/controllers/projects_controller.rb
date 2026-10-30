class ProjectsController < ApplicationController
  def index
    projects = Current.user.projects.includes(:organization).order(:name)
    @groups = projects.group_by(&:organization).sort_by { |organization, _| [ organization.personal ? 0 : 1, organization.name.downcase ] }
  end

  def new
    @project = Project.new
    @selected_organization_id = params[:organization_id]
    @organizations = creatable_organizations
  end

  def create
    attrs = params.expect(project: %i[name organization_id])
    organization = target_organization(attrs[:organization_id])
    require_role!(:member, organization)
    return if performed?

    @project = organization.projects.build(name: attrs[:name])
    if @project.save
      redirect_to project_path(@project)
    else
      @selected_organization_id = attrs[:organization_id]
      @organizations = creatable_organizations
      render :new, status: :unprocessable_content
    end
  end

  def show
    @project = current_project
  end

  def destroy
    require_role!(:admin)
    return if performed?

    current_project.destroy!
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  def target_organization(id)
    return Current.user.personal_organization || raise(ActiveRecord::RecordNotFound) if id.blank?

    Current.user.organizations.find(id)
  end

  def creatable_organizations
    roles = Membership::RANK.select { |_, rank| rank >= Membership::RANK.fetch("member") }.keys
    Current.user.organizations.merge(Membership.where(role: roles)).sort_by { |o| [ o.personal ? 0 : 1, o.name.downcase ] }
  end
end
