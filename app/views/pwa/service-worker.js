// Raider Hideout service worker. Security rules:
//  - the only thing ever cached is the /offline page;
//  - only top-level navigations are intercepted, and only to fall back to
//    /offline when the network fails. Authenticated responses are never stored;
//  - a notification click only opens same-origin URLs.
const OFFLINE_CACHE = "hideout-offline-v1"
const OFFLINE_URL = "/offline"
const FALLBACK_PATH = "/projects"

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(OFFLINE_CACHE).then((cache) => cache.add(OFFLINE_URL)).then(() => self.skipWaiting())
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

  event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL).then((cached) => cached || Response.error())))
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
      const exact = clients.find((client) => client.url === url.href)
      if (exact) return exact.focus()

      // Same page, different query (e.g. ?result=<id>): navigate so the page reacts to it.
      const samePath = clients.find((client) => new URL(client.url).pathname === url.pathname)
      if (samePath && "navigate" in samePath) {
        // navigate() rejects on a tab this worker does not control; fall back to a new window.
        return samePath.navigate(url.href)
          .then((navigated) => navigated && navigated.focus())
          .catch(() => self.clients.openWindow(url.href))
      }
      return self.clients.openWindow(url.href)
    })
  )
})
