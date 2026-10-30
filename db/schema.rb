# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_28_100000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_api_tokens_on_project_id"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
  end

  create_table "builds", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "build_key", null: false
    t.string "provider"
    t.string "build_id"
    t.string "attempt"
    t.string "ci_url"
    t.string "branch"
    t.string "commit_sha"
    t.string "commit_message"
    t.string "status", default: "passed", null: false
    t.integer "expected_shards"
    t.integer "total_count", default: 0, null: false
    t.integer "passed_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.integer "pending_count", default: 0, null: false
    t.integer "flaky_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "repository"
    t.string "default_branch"
    t.integer "pr_number"
    t.string "pr_base_branch"
    t.string "pr_head_branch"
    t.string "pr_url"
    t.integer "baseline_build_id"
    t.datetime "baseline_assigned_at"
    t.integer "quarantined_count", default: 0, null: false
    t.string "gate_status"
    t.text "gate_result"
    t.datetime "gate_evaluated_at"
    t.index ["baseline_build_id"], name: "index_builds_on_baseline_build_id"
    t.index ["project_id", "branch", "created_at"], name: "index_builds_on_project_id_and_branch_and_created_at"
    t.index ["project_id", "build_key"], name: "index_builds_on_project_id_and_build_key", unique: true
    t.index ["project_id", "pr_number"], name: "index_builds_on_project_id_and_pr_number"
    t.index ["project_id"], name: "index_builds_on_project_id"
  end

  create_table "error_groups", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "digest", null: false
    t.string "exception_class", null: false
    t.string "normalized_message", null: false
    t.string "frame", default: "", null: false
    t.text "sample_message"
    t.string "sample_app_frame"
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "digest"], name: "index_error_groups_on_project_id_and_digest", unique: true
  end

  create_table "gate_rules", force: :cascade do |t|
    t.integer "project_id", null: false
    t.integer "min_pass_rate"
    t.boolean "no_new_failures", default: false, null: false
    t.boolean "no_new_flaky", default: false, null: false
    t.integer "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_gate_rules_on_project_id", unique: true
    t.index ["updated_by_id"], name: "index_gate_rules_on_updated_by_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "token_digest", null: false
    t.integer "invited_by_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "token"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["organization_id", "email"], name: "index_invitations_one_pending_per_email", unique: true, where: "accepted_at IS NULL AND revoked_at IS NULL"
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "user_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "user_id"], name: "index_memberships_on_organization_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "notification_channels", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.boolean "enabled", default: true, null: false
    t.text "webhook_url"
    t.text "recipients"
    t.boolean "include_owner", default: true, null: false
    t.string "branch_filter", default: "default", null: false
    t.string "branch_pattern"
    t.boolean "on_failed", default: true, null: false
    t.boolean "on_recovered", default: true, null: false
    t.boolean "on_new_flaky", default: false, null: false
    t.integer "pass_rate_below"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "kind"], name: "index_notification_channels_on_project_id_and_kind"
    t.index ["project_id"], name: "index_notification_channels_on_project_id"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.integer "notification_channel_id", null: false
    t.integer "build_id"
    t.string "kind", null: false
    t.json "events", default: [], null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.string "last_error"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["build_id"], name: "index_notification_deliveries_on_build_id"
    t.index ["notification_channel_id", "build_id"], name: "index_notification_deliveries_once_per_build", unique: true, where: "kind = 'build'"
    t.index ["notification_channel_id"], name: "index_notification_deliveries_on_notification_channel_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.boolean "personal", default: false, null: false
    t.integer "personal_owner_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["personal_owner_id"], name: "index_organizations_on_personal_owner_id", unique: true
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "personal_tokens", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", limit: 8, null: false
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_personal_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_personal_tokens_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "organization_id", null: false
    t.index ["organization_id"], name: "index_projects_on_organization_id"
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "quarantine_events", force: :cascade do |t|
    t.integer "quarantine_id", null: false
    t.string "action", null: false
    t.integer "actor_id"
    t.datetime "expires_at", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_quarantine_events_on_actor_id"
    t.index ["quarantine_id"], name: "index_quarantine_events_on_quarantine_id"
  end

  create_table "quarantines", force: :cascade do |t|
    t.integer "project_id", null: false
    t.integer "test_case_id", null: false
    t.string "reason", null: false
    t.datetime "expires_at", null: false
    t.integer "created_by_id"
    t.datetime "released_at"
    t.integer "released_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_quarantines_on_created_by_id"
    t.index ["project_id", "expires_at"], name: "index_quarantines_on_project_id_and_expires_at"
    t.index ["released_by_id"], name: "index_quarantines_on_released_by_id"
    t.index ["test_case_id"], name: "index_quarantines_on_test_case_id"
  end

  create_table "runs", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "client_run_id", null: false
    t.integer "schema_version", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "duration_ms"
    t.string "branch"
    t.string "commit_sha"
    t.string "commit_message"
    t.string "ci_provider"
    t.string "build_url"
    t.string "ci_build_id"
    t.json "environment", default: {}, null: false
    t.string "status", default: "passed", null: false
    t.integer "total_count", default: 0, null: false
    t.integer "passed_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.integer "pending_count", default: 0, null: false
    t.integer "flaky_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "build_id", null: false
    t.integer "shard_index"
    t.integer "shard_total"
    t.string "shard_label"
    t.datetime "flakiness_analyzed_at"
    t.datetime "attachments_purged_at"
    t.datetime "results_purged_at"
    t.integer "quarantined_count", default: 0, null: false
    t.index ["build_id"], name: "index_runs_on_build_id"
    t.index ["created_at"], name: "index_runs_on_created_at"
    t.index ["project_id", "branch", "created_at"], name: "index_runs_on_project_id_and_branch_and_created_at"
    t.index ["project_id", "client_run_id"], name: "index_runs_on_project_id_and_client_run_id", unique: true
    t.index ["project_id"], name: "index_runs_on_project_id"
  end

  create_table "saved_views", force: :cascade do |t|
    t.integer "project_id", null: false
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "query", default: "", null: false
    t.string "level", default: "tests", null: false
    t.boolean "shared", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "shared"], name: "index_saved_views_on_project_id_and_shared"
    t.index ["project_id"], name: "index_saved_views_on_project_id"
    t.index ["user_id"], name: "index_saved_views_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "test_case_verdicts", force: :cascade do |t|
    t.integer "test_case_id", null: false
    t.string "branch", null: false
    t.boolean "flaky", default: false, null: false
    t.string "flaky_reason"
    t.float "flip_rate"
    t.integer "sample_count", default: 0, null: false
    t.integer "flaky_since_build_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["branch", "flaky"], name: "index_test_case_verdicts_on_branch_and_flaky"
    t.index ["flaky_since_build_id"], name: "index_test_case_verdicts_on_flaky_since_build_id"
    t.index ["test_case_id", "branch"], name: "index_test_case_verdicts_on_test_case_id_and_branch", unique: true
  end

  create_table "test_cases", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "test_key", null: false
    t.string "full_name", null: false
    t.string "file_path", null: false
    t.integer "line_number"
    t.string "last_status"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "test_key"], name: "index_test_cases_on_project_id_and_test_key", unique: true
    t.index ["project_id"], name: "index_test_cases_on_project_id"
  end

  create_table "test_results", force: :cascade do |t|
    t.integer "run_id", null: false
    t.integer "test_case_id", null: false
    t.string "identifier", null: false
    t.string "status", null: false
    t.integer "duration_ms", default: 0, null: false
    t.integer "attempts", default: 1, null: false
    t.boolean "retried_flaky", default: false, null: false
    t.json "tags", default: [], null: false
    t.text "failure_message"
    t.string "exception_class"
    t.text "backtrace"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "error_group_id"
    t.string "tags_text", default: "", null: false
    t.string "app_frame", limit: 500
    t.index ["error_group_id", "created_at"], name: "index_test_results_on_error_group_id_and_created_at"
    t.index ["run_id", "status"], name: "index_test_results_on_run_id_and_status"
    t.index ["run_id"], name: "index_test_results_on_run_id"
    t.index ["test_case_id", "created_at"], name: "index_test_results_on_test_case_id_and_created_at"
    t.index ["test_case_id"], name: "index_test_results_on_test_case_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "email_verified_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "projects"
  add_foreign_key "builds", "builds", column: "baseline_build_id", on_delete: :nullify
  add_foreign_key "builds", "projects"
  add_foreign_key "error_groups", "projects"
  add_foreign_key "gate_rules", "projects", on_delete: :cascade
  add_foreign_key "gate_rules", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "invitations", "organizations"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "notification_channels", "projects"
  add_foreign_key "notification_deliveries", "builds"
  add_foreign_key "notification_deliveries", "notification_channels"
  add_foreign_key "organizations", "users", column: "personal_owner_id"
  add_foreign_key "personal_tokens", "users", on_delete: :cascade
  add_foreign_key "projects", "organizations"
  add_foreign_key "quarantine_events", "quarantines", on_delete: :cascade
  add_foreign_key "quarantine_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "quarantines", "projects", on_delete: :cascade
  add_foreign_key "quarantines", "test_cases", on_delete: :cascade
  add_foreign_key "quarantines", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "quarantines", "users", column: "released_by_id", on_delete: :nullify
  add_foreign_key "runs", "builds"
  add_foreign_key "runs", "projects"
  add_foreign_key "saved_views", "projects"
  add_foreign_key "saved_views", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "test_case_verdicts", "builds", column: "flaky_since_build_id", on_delete: :nullify
  add_foreign_key "test_case_verdicts", "test_cases", on_delete: :cascade
  add_foreign_key "test_cases", "projects"
  add_foreign_key "test_results", "error_groups", on_delete: :nullify
  add_foreign_key "test_results", "runs"
  add_foreign_key "test_results", "test_cases"
end
