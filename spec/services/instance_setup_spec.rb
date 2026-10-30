require "rails_helper"

RSpec.describe InstanceSetup do
  def attrs(email = "admin@example.com", **overrides)
    { email_address: email, password: "password123", password_confirmation: "password123",
      organization_name: "Acme QA", project_name: "Checkout" }.merge(overrides)
  end

  it "creates a verified admin, a personal and a team organization, the project and a CI token" do
    result = described_class.new(attrs).save
    expect(result).to be_a(InstanceSetup::Result)
    expect(result.user).to be_verified
    expect(result.user.personal_organization).to be_present
    expect(result.organization.name).to eq("Acme QA")
    expect(result.organization.role_for(result.user)).to eq("owner")
    expect(result.project.organization).to eq(result.organization)
    token = ApiToken.authenticate(result.token)
    expect(token.project).to eq(result.project)
    expect(token.name).to eq("CI")
  end

  it "is pending only while there are no users" do
    expect(described_class.pending?).to be(true)
    create(:user)
    expect(described_class.pending?).to be(false)
  end

  it "refuses once any user exists" do
    create(:user)
    expect { described_class.new(attrs).save }.to raise_error(InstanceSetup::AlreadyDone)
  end

  it "validates the names before touching the database" do
    setup = described_class.new(attrs(organization_name: "", project_name: " "))
    expect(setup.save).to be(false)
    expect(setup.errors.full_messages).to include("Organization name can't be blank", "Project name can't be blank")
  end

  it "rolls everything back when the user is invalid" do
    setup = described_class.new(attrs(password: "short", password_confirmation: "short"))
    expect(setup.save).to be(false)
    expect(setup.errors.full_messages).to include(a_string_starting_with("Password is too short"))
    expect([ User.count, Organization.count, Project.count, ApiToken.count ]).to eq([ 0, 0, 0, 0 ])
  end

  context "when two setups run at once" do
    self.use_transactional_tests = false

    after { [ ApiToken, Project, Membership, Organization, User ].each(&:delete_all) }

    it "lets exactly one through" do
      gate = Queue.new
      threads = %w[a@example.com b@example.com].map do |email|
        Thread.new do
          gate.pop
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.new(attrs(email)).save
          rescue InstanceSetup::AlreadyDone
            :already_done
          end
        end
      end
      2.times { gate << true }
      results = threads.map(&:value)
      expect(results.count { |result| result.is_a?(InstanceSetup::Result) }).to eq(1)
      expect(results).to include(:already_done)
      expect(User.count).to eq(1)
    end
  end
end
