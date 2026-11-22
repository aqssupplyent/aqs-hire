// AQS Hire: hantar notifikasi job kepada telefon pemandu (Web Push)
// Supabase → Edge Functions → nama fungsi: notify
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const dmy = (iso?: string) => (iso ? iso.slice(8, 10) + "/" + iso.slice(5, 7) + "/" + iso.slice(0, 4) : "");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const URL_ = Deno.env.get("SUPABASE_URL")!;
  const pick = (name: string) => { try { const o = JSON.parse(Deno.env.get(name) || "{}"); return o.default || Object.values(o)[0] || ""; } catch (_) { return ""; } };
  const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || pick("SUPABASE_SECRET_KEYS");
  const ANON = Deno.env.get("SUPABASE_ANON_KEY") || pick("SUPABASE_PUBLISHABLE_KEYS");
  if (!SRK || !ANON) return json({ error: "missing_keys" }, 500);
  const admin = createClient(URL_, SRK, { auth: { persistSession: false } });
  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch (_) { /* kosong */ }

  // Kunci VAPID: dicipta sekali dan disimpan dalam push_keys
  let { data: k } = await admin.from("push_keys").select("*").eq("id", 1).maybeSingle();
  if (!k) {
    const g = webpush.generateVAPIDKeys();
    await admin.from("push_keys").upsert({ id: 1, public_key: g.publicKey, private_key: g.privateKey });
    ({ data: k } = await admin.from("push_keys").select("*").eq("id", 1).maybeSingle());
  }
  if (!k) return json({ error: "no_keys" }, 500);
  if (body.action === "key") return json({ publicKey: k.public_key });
  if (body.action !== "notify" || !body.org || !body.jobId) return json({ error: "bad_request" }, 400);

  // Hanya admin / staf dengan akses Rekod Kerja boleh hantar
  const user = createClient(URL_, ANON, {
    global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    auth: { persistSession: false },
  });
  let allowed = false;
  const p = await user.rpc("has_perm", { o: body.org, p: "kerja" });
  if (!p.error) allowed = !!p.data;
  else { const a = await user.rpc("is_org_admin", { o: body.org }); allowed = !a.error && !!a.data; }
  if (!allowed) return json({ error: "forbidden" }, 403);

  const { data: job } = await admin.from("jobs").select("data").eq("org", body.org).eq("id", body.jobId).maybeSingle();
  if (!job) return json({ error: "not_found" }, 404);
  const j = job.data || {};
  if (!j.driverId) return json({ sent: 0, reason: "no_driver" });

  const { data: cfg } = await admin.from("config").select("data").eq("org", body.org).eq("id", "company").maybeSingle();
  // deno-lint-ignore no-explicit-any
  const drs: any[] = (cfg && cfg.data && cfg.data.drivers) || [];
  const d = drs.find((x) => x.id === j.driverId);
  let emails: string[] = [];
  if (d && d.email) emails = [String(d.email).toLowerCase()];
  else {
    const bound = new Set(drs.filter((x) => x.email).map((x) => String(x.email).toLowerCase()));
    const { data: m } = await admin.from("members").select("email").eq("org", body.org).eq("role", "driver");
    emails = (m || []).map((x) => String(x.email).toLowerCase()).filter((e) => !bound.has(e));
  }
  if (!emails.length) return json({ sent: 0, reason: "no_account" });

  const { data: subs } = await admin.from("push_subs").select("endpoint,sub").eq("org", body.org).in("email", emails);
  if (!subs || !subs.length) return json({ sent: 0, reason: "no_subscription" });

  let cust = j.customerName || "";
  if (j.customerId) {
    const { data: c } = await admin.from("customers").select("data").eq("org", body.org).eq("id", j.customerId).maybeSingle();
    if (c && c.data && c.data.name) cust = c.data.name;
  }
  const site = typeof body.site === "string" && /^https:\/\//.test(body.site) ? body.site : "";
  const payload = JSON.stringify({
    title: "Job baharu: " + (j.no || ""),
    body: [cust, [dmy(j.startDate), j.time].filter(Boolean).join(" · "), [j.pickup, j.dropoff].filter(Boolean).join(" → ")].filter(Boolean).join("\n"),
    tag: "job-" + body.jobId,
    url: site ? site + "#tugasan" : "./#tugasan",
  });
  webpush.setVapidDetails(site || "mailto:noreply@example.com", k.public_key, k.private_key);
  let sent = 0;
  for (const s of subs) {
    try { await webpush.sendNotification(s.sub, payload, { TTL: 86400 }); sent++; }
    // deno-lint-ignore no-explicit-any
    catch (e: any) { if (e && (e.statusCode === 404 || e.statusCode === 410)) await admin.from("push_subs").delete().eq("endpoint", s.endpoint); }
  }
  return json({ sent, total: subs.length });
});
