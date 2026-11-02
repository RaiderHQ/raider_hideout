# Account → Phone notifications: the browser registers its push subscription (JSON from
# PushSubscription.toJSON()) and the user can remove their own devices. Every lookup goes
# through Current.user, so another user's subscription is never found (404).
# The endpoint is an address the server will POST to later, so PushSubscription allowlists it.
class PushSubscriptionsController < ApplicationController
  def create
    subscription = PushSubscription.find_by(endpoint: endpoint_param)
    return render_errors([ "Endpoint is already registered" ]) if subscription && subscription.user_id != Current.user.id

    subscription ||= Current.user.push_subscriptions.new(endpoint: endpoint_param,
                                                         device_label: device_label)
    subscription.assign_attributes(p256dh: key_param(:p256dh), auth: key_param(:auth))
    subscription.device_label = device_label if subscription.new_record?

    if subscription.save
      render json: { id: subscription.id }, status: :created
    else
      render_errors(subscription.errors.full_messages)
    end
  rescue ActiveRecord::RecordNotUnique
    # A concurrent post of the same endpoint won the insert: if it is this user's, treat ours as the upsert.
    existing = Current.user.push_subscriptions.find_by(endpoint: endpoint_param)
    return render_errors([ "Endpoint is already registered" ]) unless existing

    existing.update(p256dh: key_param(:p256dh), auth: key_param(:auth)) ?
      render(json: { id: existing.id }, status: :created) : render_errors(existing.errors.full_messages)
  end

  def destroy
    Current.user.push_subscriptions.find(params[:id]).destroy!
    redirect_to phone_notifications_path, notice: "Device removed."
  end

  private

  def render_errors(messages)
    render json: { errors: messages }, status: :unprocessable_content
  end

  def endpoint_param = string_param(params[:endpoint])

  def key_param(name)
    keys = params[:keys]
    string_param(keys.is_a?(ActionController::Parameters) ? keys[name] : nil)
  end

  # Only plain strings are accepted; arrays and hashes from a hand-made request become blank.
  def string_param(value) = value.is_a?(String) ? value : nil

  def device_label
    label = string_param(params[:device_label]).to_s.strip
    label = PushSubscription.label_from_user_agent(request.user_agent) if label.empty?
    label.first(PushSubscription::MAX_LABEL_LENGTH)
  end
end
