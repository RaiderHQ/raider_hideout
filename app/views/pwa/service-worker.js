// Raider Hideout service worker. Security rules:
//  - the only thing ever cached is the /offline page;
//  - only top-level navigations are intercepted, and only to fall back to
//    /offline when the network fails. Authenticated responses are never stored;
//  - a notification click only opens same-origin URLs.
const OFFLINE_CACHE = "hideout-offline-v1" // keep in step with the cache name in install
const OFFLINE_URL = "/offline"
const FALLBACK_PATH = "/projects"

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open("hideout-offline-v1").then((cache) => cache.add("/offline")).then(() => self.skipWaiting())
  )
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(
        names.filter((name) => name.startsWith("hideout-offline-") && name !== OFFLINE_CACHE)
             .map((name) => caches.delete(name))
      ))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  if (request.mode !== "navigate") return

  event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)))
})

self.addEventListener("push", (event) => {
  let payload = {}
  try {
    payload = event.data ? event.data.json() : {}
  } catch (_error) {
    payload = {}
  }
  if (payload === null || typeof payload !== "object") payload = {}

  const title = typeof payload.title === "string" && payload.title ? payload.title : "Raider Hideout"
  const body = typeof payload.body === "string" ? payload.body : ""
  const path = typeof payload.path === "string" ? payload.path : FALLBACK_PATH

  // Always show something: a push without a notification is penalised by browsers.
  event.waitUntil(
    self.registration.showNotification(title, {
      body: body,
      data: { path: path },
      icon: "/icon-192.png",
      badge: "/icon-192.png"
    })
  )
})

function parseUrl(path) {
  try {
    return new URL(path, self.location.origin)
  } catch (_error) {
    return null
  }
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close()

  const data = event.notification.data
  const path = data && typeof data.path === "string" ? data.path : FALLBACK_PATH

  let url = parseUrl(path)
  if (!(url && url.origin === self.location.origin)) url = parseUrl(FALLBACK_PATH)

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if (new URL(client.url).pathname === url.pathname && "focus" in client) return client.focus()
      }
      return self.clients.openWindow(url.href)
    })
  )
})
