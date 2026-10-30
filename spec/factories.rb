FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "password123" }
    email_verified_at { Time.current }

    trait(:unverified) { email_verified_at { nil } }

    # Mirrors sign-up: every user owns a personal organization.
    transient do
      with_personal_organization { true }
    end

    after(:create) do |user, ctx|
      Organization.create_personal!(user) if ctx.with_personal_organization && !user.personal_organization
    end
  end

  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }

    trait :personal do
      personal { true }
      personal_owner { association :user, with_personal_organization: false }

      after(:create) do |organization|
        organization.memberships.create!(user: organization.personal_owner, role: "owner")
      end
    end
  end

  factory :membership do
    organization
    user
    role { "member" }
  end

  factory :invitation do
    organization
    sequence(:email) { |n| "guest#{n}@example.com" }
    role { "member" }
    invited_by factory: :user
    token_digest { Invitation.digest(Invitation.generate_token) }
    expires_at { Invitation::LIFETIME.from_now }
  end

  factory :project do
    sequence(:name) { |n| "Project #{n}" }

    # `create(:project, owner: user)` puts the project in the user's personal
    # organization (created if missing); otherwise it gets a fresh organization.
    transient do
      owner { nil }
    end

    organization do
      if owner
        owner.personal_organization || Organization.create_personal!(owner)
      else
        association :organization
      end
    end
  end

  factory :build do
    project
    sequence(:build_key) { |n| "build-#{n}" }
    branch { "main" }
    commit_sha { "abc123" }
  end

  factory :run do
    project
    build { association :build, project: project }
    sequence(:client_run_id) { |n| "run-#{n}" }
    schema_version { 1 }
    branch { "main" }
    commit_sha { "abc123" }
  end

  factory :test_case do
    project
    sequence(:full_name) { |n| "Example #{n}" }
    file_path { "spec/example_spec.rb" }
    test_key { TestCase.key_for(file_path, full_name) }
  end

  factory :test_case_verdict do
    test_case
    branch { "main" }
    flaky { false }
    sample_count { Flakiness::Analyzer::MIN_SAMPLES }
  end

  factory :notification_channel do
    project
    kind { "slack" }
    sequence(:name) { |n| "#qa-alerts-#{n}" }
    webhook_url { "https://hooks.slack.com/services/T0/B0/abcdWXYZ" }

    trait :slack

    trait :teams do
      kind { "teams" }
      webhook_url { "https://prod-12.westeurope.logic.azure.com/workflows/abc/triggers/manual/paths/invoke?sig=s" }
    end

    trait :email do
      kind { "email" }
      webhook_url { nil }
      recipients { "qa@example.com" }
    end
  end

  factory :notification_delivery do
    notification_channel
    build { association :build, project: notification_channel.project }
    kind { "build" }
    events { [ "failed" ] }
  end

  factory :error_group do
    project
    sequence(:digest) { |n| Digest::SHA256.hexdigest("group-#{n}") }
    exception_class { "RuntimeError" }
    normalized_message { "boom" }
    frame { "" }
    first_seen_at { Time.current }
    last_seen_at { Time.current }
  end

  factory :test_result do
    run
    test_case { association :test_case, project: run.project }
    sequence(:identifier) { |n| "./spec/example_spec.rb[1:#{n}]" }
    status { "passed" }
  end

  factory :saved_view do
    project
    user
    sequence(:name) { |n| "View #{n}" }
    query { "status:failed" }
    level { "tests" }
  end

  factory :quarantine do
    test_case
    project { test_case.project }
    reason { "Known flaky: waits on the mail server" }
    expires_at { Quarantine::DEFAULT_DURATION.days.from_now }
    created_by factory: :user
  end

  factory :gate_rule do
    project
  end
end
