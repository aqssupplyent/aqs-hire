// AQS Hire service worker v2: notifikasi job + nombor pada ikon (tiada cache, supaya kemas kini sentiasa terus sampai)
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});

self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : "" }; }
  const title = d.title || "Job baharu";
  e.waitUntil(Promise.all([bumpBadge(d.badge), self.registration.showNotification(title, {
    body: d.body || "",
    icon: "assets/icon-192.png",
    badge: "assets/icon-192.png",
    tag: d.tag || "aqs-job",
    renotify: true,
    data: { url: d.url || "./#tugasan" }
  })]));
});

// Nombor merah pada ikon apps (seperti WhatsApp)
async function bumpBadge(n) {
  try {
    if (!self.navigator || !self.navigator.setAppBadge) return;
    const c = await caches.open("aqs-badge");
    let cur = 0;
    const r = await c.match("count");
    if (r) cur = parseInt(await r.text(), 10) || 0;
    const next = typeof n === "number" ? n : cur + 1;
    await c.put("count", new Response(String(next)));
    await self.navigator.setAppBadge(next);
  } catch (_) {}
}

self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "./#tugasan", self.registration.scope).href;
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const c of all) { if (c.url.startsWith(self.registration.scope)) { await c.focus(); try { c.navigate(url); } catch (_) {} return; } }
    await self.clients.openWindow(url);
  })());
});
