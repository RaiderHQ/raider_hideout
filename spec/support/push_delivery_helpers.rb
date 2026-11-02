require_relative "push_helpers"

module PushDeliveryHelpers
  # A user in the project's organization with one subscribed device.
  def subscribe_member(project, endpoint: fcm_endpoint(SecureRandom.hex(4)), role: "member")
    user = create(:user)
    Membership.create!(organization: project.organization, user: user, role: role)
    [ user, create_subscription(user, endpoint) ]
  end

  # Real P-256 point: the push is actually encrypted to it.
  def create_subscription(user, endpoint)
    PushSubscription.create!(user: user, endpoint: endpoint, p256dh: WebPush.generate_key.public_key, auth: valid_auth)
  end

  def add_failed_result(build, name: "Checkout fails")
    run = build.runs.first || create(:run, project: build.project, build: build)
    create(:test_result, run: run, status: "failed", test_case: create(:test_case, project: build.project, full_name: name))
  end
end

RSpec.configure do |c|
  c.include PushDeliveryHelpers, type: :system
  c.include PushDeliveryHelpers, file_path: %r{spec/(jobs|services/push)/}
  c.include PushHelpers, file_path: %r{spec/(jobs|services/push)/}
end
