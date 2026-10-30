# Quarantine, extend and release a test (spec §5.4). Viewers may look; members and up may change.
class QuarantinesController < ApplicationController
  EVENTS_LIMIT = 50
  INACTIVE = "This quarantine is no longer active".freeze

  before_action(only: %i[create update destroy]) { require_role!(:member) }

  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to_test_page alert: error.record.errors.full_messages.to_sentence
  end
  rescue_from(Quarantine::Inactive) { redirect_to_test_page notice: INACTIVE }
  rescue_from Quarantine::AlreadyQuarantined do |error|
    redirect_to_test_page alert: "Already quarantined until #{helpers.quarantine_date(error.quarantine.expires_at)}"
  end

  def index
    @quarantines = current_project.quarantines.active.includes(:test_case, :created_by).order(:expires_at, :id)
    @events = QuarantineEvent.for_project(current_project).includes(:actor, quarantine: :test_case)
                             .newest_first.limit(EVENTS_LIMIT)
  end

  def create
    @test_case = current_project.test_cases.find(params[:test_case_id])
    quarantine = Quarantine.quarantine!(test_case: @test_case, user: Current.user, reason: quarantine_params[:reason].to_s,
                                        days: days_param)
    redirect_to_test_page notice: "Quarantined until #{helpers.quarantine_date(quarantine.expires_at)}."
  end

  def update
    quarantine = find_quarantine
    quarantine.extend_by!(user: Current.user, days: days_param, note: quarantine_params[:note])
    redirect_to_test_page notice: "Quarantine extended until #{helpers.quarantine_date(quarantine.expires_at)}."
  end

  def destroy
    find_quarantine.release!(user: Current.user, note: quarantine_params[:note])
    redirect_to_test_page notice: "Quarantine released."
  end

  private

  # A scalar quarantine param (quarantine=foo) is a malformed request: 400, not 500.
  def quarantine_params
    raw = params.fetch(:quarantine, {})
    raise ActionController::BadRequest, "quarantine must be a hash" unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

    raw.permit(:reason, :days, :note)
  end

  def days_param = quarantine_params[:days].presence || Quarantine::DEFAULT_DURATION

  def find_quarantine
    quarantine = current_project.quarantines.find(params[:id])
    @test_case = quarantine.test_case
    quarantine
  end

  def redirect_to_test_page(flash_options)
    redirect_to project_test_case_path(current_project, @test_case, anchor: "quarantine"), **flash_options
  end
end
