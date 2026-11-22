// AQS Hire service worker: notifikasi job sahaja (tiada cache, supaya kemas kini sentiasa terus sampai)
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});

self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : "" }; }
  const title = d.title || "Job baharu";
  e.waitUntil(self.registration.showNotification(title, {
    body: d.body || "",
    icon: "assets/icon-192.png",
    badge: "assets/icon-192.png",
    tag: d.tag || "aqs-job",
    renotify: true,
    data: { url: d.url || "./#tugasan" }
  }));
});

self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "./#tugasan", self.registration.scope).href;
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const c of all) { if (c.url.startsWith(self.registration.scope)) { await c.focus(); try { c.navigate(url); } catch (_) {} return; } }
    await self.clients.openWindow(url);
  })());
});
