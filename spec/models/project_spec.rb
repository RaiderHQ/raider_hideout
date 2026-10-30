require "rails_helper"

RSpec.describe Project do
  it "derives a unique slug from the name" do
    first = create(:project, name: "Demo App")
    second = create(:project, name: "Demo App")
    expect([ first.slug, second.slug ]).to eq(%w[demo-app demo-app-2])
    expect(first.to_param).to eq("demo-app")
  end

  it "never takes a slug that collides with a route action" do
    project = create(:project, name: "New")
    expect(project.slug).to eq("new-2")
    expect(create(:project, name: "Edit").slug).to eq("edit-2")
    expect(Rails.application.routes.recognize_path(Rails.application.routes.url_helpers.project_path(project)))
      .to include(controller: "projects", action: "show", id: "new-2")
  end

  it "requires a name" do
    expect(build(:project, name: "").valid?).to be(false)
  end

  describe "#default_branch" do
    let(:project) { create(:project) }

    it "is the most recent build's reported default branch" do
      create(:build, project: project, branch: "x", default_branch: "develop", created_at: 2.days.ago)
      create(:build, project: project, branch: "y", default_branch: "trunk", created_at: 1.day.ago)
      create(:build, project: project, branch: "main", default_branch: nil)
      expect(project.default_branch).to eq("trunk")
    end

    it "falls back to main, then master, then main" do
      expect(create(:project).default_branch).to eq("main")
      create(:build, project: project, branch: "master")
      expect(Project.find(project.id).default_branch).to eq("master")
      create(:build, project: project, branch: "main")
      expect(Project.find(project.id).default_branch).to eq("main")
    end
  end

  describe "#flaky_count" do
    it "counts flaky verdicts on the default branch only" do
      project = create(:project)
      create(:build, project: project, branch: "main")
      2.times { create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "main", flaky: true) }
      create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "main", flaky: false)
      create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "feature", flaky: true)
      create(:test_case_verdict, test_case: create(:test_case), branch: "main", flaky: true)
      expect(project.flaky_count).to eq(2)
    end
  end
end
