import { Controller } from "@hotwired/stimulus"

// Turns phone notifications on for this browser: asks permission, subscribes through the
// service worker's push manager, then registers the subscription with the server.
export default class extends Controller {
  static values = { publicKey: String, url: String }
  static targets = ["message"]

  async subscribe(event) {
    event.preventDefault()
    this.show("")
    try {
      if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) {
        return this.show("This browser cannot show push notifications.")
      }
      const permission = await Notification.requestPermission()
      if (permission !== "granted") {
        return this.show("Notifications are blocked for this site in your browser settings.")
      }
      const registration = await navigator.serviceWorker.ready
      const subscription = await this.currentSubscription(registration)
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
        },
        body: JSON.stringify(subscription.toJSON())
      })
      if (!response.ok) return this.show("Could not turn on notifications. Try again.")
      Turbo.visit(location.href)
    } catch (error) {
      this.show("Could not turn on notifications. Try again.")
    }
  }

  // Reuses this browser's subscription when it was made with our key (the server upserts it, so a
  // re-tap adds no device). A subscription made with another key makes subscribe() throw, so replace it.
  async currentSubscription(registration) {
    const applicationServerKey = this.urlBase64ToUint8Array(this.publicKeyValue)
    const existing = await registration.pushManager.getSubscription()
    if (existing) {
      const current = existing.options && existing.options.applicationServerKey
      if (current && this.sameBytes(new Uint8Array(current), applicationServerKey)) return existing
      await existing.unsubscribe()
    }
    return registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey })
  }

  sameBytes(a, b) {
    return a.length === b.length && a.every((byte, i) => byte === b[i])
  }

  show(text) {
    if (this.hasMessageTarget) this.messageTarget.textContent = text
  }

  urlBase64ToUint8Array(value) {
    const padded = value + "=".repeat((4 - (value.length % 4)) % 4)
    const raw = atob(padded.replace(/-/g, "+").replace(/_/g, "/"))
    return Uint8Array.from(raw, (char) => char.charCodeAt(0))
  }
}
