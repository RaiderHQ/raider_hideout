Rails.application.routes.draw do
  get "attachments/:id", to: "attachments#show", as: :attachment
  resource :session
  resource :setup, only: %i[show create]
  resources :passwords, only: %i[new create]
  # Token travels as a query/form param so it is filtered from logs (never a path segment).
  get "passwords/edit", to: "passwords#edit", as: :edit_password
  match "passwords", to: "passwords#update", via: %i[patch put], as: :password
  resource :registration, only: %i[new create]
  resource :email_verification, path: "verify_email", only: %i[show create], as: :verify_email
  get "verify_email/confirm", to: "email_verifications#update", as: :verify_email_confirm
  resources :personal_tokens, only: %i[index create destroy], path: "account/tokens"
  resources :organizations do
    resources :memberships, only: %i[index update destroy]
    resources :invitations, only: %i[create destroy] do
      member { post :resend }
    end
  end
  get "/invitations/accept", to: "invitation_acceptances#show", as: :invitation_acceptance
  post "/invitations/accept", to: "invitation_acceptances#create", as: :accept_invitation
  resources :projects, only: %i[index new create show destroy] do
    resources :api_tokens, only: %i[index create destroy]
    resources :builds, only: %i[index show]
    resources :errors, only: %i[index show]
    resources :notification_channels, path: "notifications", except: :show do
      member { post :test }
    end
    resource :gate, only: %i[show update], controller: "gate_rules"
    resources :runs, only: %i[index show]
    resources :test_cases, only: :show do
      resources :quarantines, only: :create
    end
    resources :quarantines, only: %i[update destroy]
    get "quarantine", to: "quarantines#index", as: :quarantined_tests
    get "flaky", to: "flaky_tests#index", as: :flaky_tests
    get "explore", to: "explore#show", as: :explore
    get "analytics", to: "analytics#show", as: :analytics
    resources :saved_views, only: %i[create update destroy]
  end
  namespace :api do
    namespace :v1 do
      resources :runs, only: :create
      get "builds/summary", to: "build_summaries#show"
      get "builds/gate", to: "build_gates#show"
      get "quarantine", to: "quarantines#index"
      get "openapi.json", to: "openapi#show", as: :openapi, format: false
      # Personal-token API (spec §5). Paths and parameter names must match docs/openapi.yaml.
      scope module: :public do
        get "projects", to: "projects#index", as: :projects
        get "projects/:project_slug", to: "projects#show", as: :project
        get "projects/:project_slug/builds", to: "builds#index", as: :project_builds
        get "projects/:project_slug/builds/:id", to: "builds#show", as: :project_build
        get "projects/:project_slug/tests", to: "tests#index", as: :project_tests
        get "projects/:project_slug/tests/:id", to: "tests#show", as: :project_test
        get "projects/:project_slug/errors", to: "errors#index", as: :project_errors
        get "projects/:project_slug/errors/:id", to: "errors#show", as: :project_error
        get "projects/:project_slug/flaky", to: "flaky#index", as: :project_flaky
        get "projects/:project_slug/quarantines", to: "quarantines#index", as: :project_quarantines
      end
    end
  end
  post "mcp", to: "mcp#create"
  match "mcp", to: "mcp#method_not_allowed", via: %i[get delete]
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
  root "projects#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
