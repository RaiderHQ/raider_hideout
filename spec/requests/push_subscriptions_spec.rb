require "rails_helper"

RSpec.describe "Push subscriptions", type: :request do
  let(:user) { create(:user) }
  let(:payload) { { endpoint: fcm_endpoint, keys: { p256dh: valid_p256dh, auth: valid_auth } } }

  def post_json(body, headers = {})
    post push_subscriptions_path, params: body.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers)
  end

  context "signed in" do
    before { sign_in(user) }

    it "stores the subscription and answers 201 with its id" do
      post_json(payload, "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)")
      expect(response).to have_http_status(:created)
      sub = user.push_subscriptions.sole
      expect(response.parsed_body).to eq("id" => sub.id)
      expect(sub).to have_attributes(endpoint: fcm_endpoint, p256dh: valid_p256dh, auth: valid_auth, device_label: "iPhone")
    end

    it "accepts Apple and Mozilla endpoints" do
      post_json(payload.merge(endpoint: "https://web.push.apple.com/abc"))
      post_json(payload.merge(endpoint: "https://updates.push.services.mozilla.com/wpush/v2/abc"))
      expect(user.push_subscriptions.count).to eq(2)
    end

    it "lets a viewer subscribe their own device" do
      viewer = create(:user)
      create(:membership, user: viewer, organization: create(:organization), role: "viewer")
      delete session_path
      sign_in(viewer)
      post_json(payload)
      expect(response).to have_http_status(:created)
      expect(viewer.push_subscriptions.count).to eq(1)
    end

    [
      "http://fcm.googleapis.com/fcm/send/abc",
      "https://10.0.0.1/fcm/send/abc",
      "https://fcm.googleapis.com:8443/fcm/send/abc",
      "https://evil.example/fcm/send/abc",
      "https://fcm.googleapis.com.evil.example/fcm/send/abc"
    ].each do |endpoint|
      it "rejects #{endpoint} with 422 and stores nothing" do
        post_json(payload.merge(endpoint: endpoint))
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to be_present
        expect(PushSubscription.count).to eq(0)
      end
    end

    it "accepts an extra host from HIDEOUT_PUSH_HOSTS" do
      ENV["HIDEOUT_PUSH_HOSTS"] = "push.example.org"
      post_json(payload.merge(endpoint: "https://push.example.org/x"))
      expect(response).to have_http_status(:created)
    ensure
      ENV.delete("HIDEOUT_PUSH_HOSTS")
    end

    it "rejects bad key lengths" do
      post_json(payload.merge(keys: { p256dh: valid_p256dh, auth: b64url([ 1, 2, 3 ]) }))
      expect(response).to have_http_status(:unprocessable_content)
      post_json(payload.merge(keys: nil))
      expect(response).to have_http_status(:unprocessable_content)
      post_json({ endpoint: [ fcm_endpoint ], keys: { p256dh: [ 1 ], auth: { a: 1 } } })
      expect(response).to have_http_status(:unprocessable_content)
      expect(PushSubscription.count).to eq(0)
    end

    it "updates the keys when the same user posts the same endpoint again" do
      post_json(payload)
      new_auth = b64url(Array.new(16, 9))
      post_json(payload.merge(keys: { p256dh: valid_p256dh, auth: new_auth }))
      expect(response).to have_http_status(:created)
      expect(user.push_subscriptions.sole.auth).to eq(new_auth)
    end

    it "gives 422 and leaves the row alone when the endpoint belongs to another user" do
      other = create(:user)
      theirs = other.push_subscriptions.create!(endpoint: fcm_endpoint, p256dh: valid_p256dh, auth: valid_auth, device_label: "Android")
      post_json(payload.merge(keys: { p256dh: valid_p256dh, auth: b64url(Array.new(16, 7)) }))
      expect(response).to have_http_status(:unprocessable_content)
      expect(theirs.reload).to have_attributes(user_id: other.id, auth: valid_auth, device_label: "Android")
      expect(user.push_subscriptions.count).to eq(0)
    end

    it "uses a supplied label, truncated to 60 characters" do
      post_json(payload.merge(device_label: "L" * 80))
      expect(user.push_subscriptions.sole.device_label).to eq("L" * 60)
    end

    it "removes the user's own subscription" do
      sub = user.push_subscriptions.create!(endpoint: fcm_endpoint, p256dh: valid_p256dh, auth: valid_auth)
      delete push_subscription_path(sub)
      expect(response).to redirect_to(phone_notifications_path)
      expect(PushSubscription.count).to eq(0)
    end

    it "gives 404 for another user's subscription and keeps it" do
      theirs = create(:user).push_subscriptions.create!(endpoint: fcm_endpoint, p256dh: valid_p256dh, auth: valid_auth)
      delete push_subscription_path(theirs)
      expect(response).to have_http_status(:not_found)
      expect(PushSubscription.exists?(theirs.id)).to be(true)
    end
  end

  it "redirects a signed-out visitor to sign in and stores nothing" do
    post_json(payload)
    expect(response).to redirect_to(new_session_path)
    expect(PushSubscription.count).to eq(0)
  end

  it "enforces CSRF: 422 without a token" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in(user)
    post_json(payload)
    expect(response).to have_http_status(:unprocessable_content)
    expect(PushSubscription.count).to eq(0)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
