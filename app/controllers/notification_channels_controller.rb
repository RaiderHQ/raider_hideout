class NotificationChannelsController < ApplicationController
  before_action(except: :index) { require_role!(:member) }
  before_action :set_channel, only: %i[edit update destroy test]

  def index
    @channels = current_project.notification_channels.order(:created_at).to_a
    ids = @channels.map(&:id)
    @last_deliveries = NotificationDelivery
                       .where(id: NotificationDelivery.where(notification_channel_id: ids).group(:notification_channel_id).select("MAX(id)"))
                       .index_by(&:notification_channel_id)
  end

  def new
    @channel = current_project.notification_channels.new(kind: requested_kind)
  end

  def create
    kind = params.dig(:notification_channel, :kind)
    raise ActiveRecord::RecordNotFound if kind == "email" && !Hideout.mail_enabled?

    attrs = channel_params
    attrs = attrs.except(:webhook_url) if kind == "email"
    @channel = current_project.notification_channels.new(attrs.merge(kind: kind))
    if @channel.save
      redirect_to project_notification_channels_path(current_project), notice: "Channel created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    attrs = channel_params
    attrs = attrs.except(:webhook_url) if attrs[:webhook_url].blank? || !@channel.webhook?
    if @channel.update(attrs)
      redirect_to project_notification_channels_path(current_project), notice: "Channel updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @channel.destroy!
    redirect_to project_notification_channels_path(current_project), notice: "Channel deleted."
  end

  def test
    delivery = @channel.notification_deliveries.create!(kind: "test", events: [])
    flash_for(delivery)
    redirect_to project_notification_channels_path(current_project)
  end

  private

  def flash_for(delivery)
    begin
      DeliverNotificationJob.perform_now(delivery.id)
    rescue StandardError => e
      delivery.reload.update!(last_error: @channel.redact("unexpected #{e.class}: #{e.message}").truncate(500))
    end
    delivery.reload
    case delivery.status
    when "sent" then flash[:notice] = "Test sent to #{@channel.name}"
    when "pending" then flash[:alert] = "Test failed: #{delivery.last_error.presence || "unknown error"} (will retry)"
    else flash[:alert] = "Test failed: #{delivery.last_error}"
    end
  end

  def set_channel
    @channel = current_project.notification_channels.find(params[:id])
    @stored_target = @channel.masked_target
  end

  def requested_kind
    NotificationChannel.available_kinds.include?(params[:kind]) ? params[:kind] : "slack"
  end

  def channel_params
    params.expect(notification_channel: %i[name enabled webhook_url recipients include_owner branch_filter
                                           branch_pattern on_failed on_recovered on_new_flaky pass_rate_below])
  end
end
