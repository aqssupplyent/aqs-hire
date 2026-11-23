// AQS Hire: notifikasi telefon (Web Push) untuk pemandu dan admin
// Supabase → Edge Functions → nama fungsi: notify  (Verify JWT: OFF)
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
const rm = (x: unknown) => "RM " + Number(x || 0).toLocaleString("en-MY", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const URL_ = Deno.env.get("SUPABASE_URL")!;
  // deno-lint-ignore no-explicit-any
  const pick = (name: string): string => { try { const o: any = JSON.parse(Deno.env.get(name) || "{}"); return String(o.default || Object.values(o)[0] || ""); } catch (_) { return ""; } };
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
  if (body.action !== "notify" && body.action !== "event") return json({ error: "bad_request" }, 400);

  const user = createClient(URL_, ANON, {
    global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    auth: { persistSession: false },
  });
  const site = typeof body.site === "string" && /^https:\/\//.test(body.site) ? body.site : "";

  // Tentukan syarikat & job (daripada log masuk, atau pautan vendor / PIC)
  let org = String(body.org || ""), jobId = String(body.jobId || ""), actor = "";
  if (body.action === "event" && (body.picToken || body.vendorToken)) {
    const t = body.picToken ? "pic_links" : "do_links";
    const { data: l } = await admin.from(t).select("*").eq("token", String(body.picToken || body.vendorToken)).maybeSingle();
    if (!l) return json({ error: "forbidden" }, 403);
    org = l.org; jobId = String(body.jobId || l.job_id);
    const ids: string[] = l.job_ids || [l.job_id];
    if (!ids.includes(jobId)) return json({ error: "forbidden" }, 403);
  } else {
    if (!org || !jobId) return json({ error: "bad_request" }, 400);
    const perm = body.action === "notify" ? "kerja" : "";
    let allowed = false;
    if (perm) {
      const p = await user.rpc("has_perm", { o: org, p: perm });
      if (!p.error) allowed = !!p.data;
      else { const a = await user.rpc("is_org_admin", { o: org }); allowed = !a.error && !!a.data; }
    } else { const m = await user.rpc("is_member", { o: org }); allowed = !m.error && !!m.data; }
    if (!allowed) return json({ error: "forbidden" }, 403);
    const u = await user.auth.getUser(); actor = String((u.data && u.data.user && u.data.user.email) || "").toLowerCase();
  }

  // Tuntutan kos (resit) dari pemandu → admin / staf dengan akses Kos Lori
  if (body.action === "event" && body.kind === "claim") {
    const { data: cr } = await admin.from("costs").select("data").eq("org", org).eq("id", jobId).maybeSingle();
    if (!cr) return json({ error: "not_found" }, 404);
    const c = cr.data || {};
    const CAT: Record<string, string> = { toll: "Tol", fuel: "Minyak", repair: "Pembaikan & Servis", tyre: "Tayar", parking: "Parking / Saman", other: "Lain-lain" };
    const { data: m } = await admin.from("members").select("email,role,perms").eq("org", org);
    // deno-lint-ignore no-explicit-any
    const to = (m || []).filter((x: any) => x.role === "admin" || (x.role === "staff" && Array.isArray(x.perms) && x.perms.includes("kos")))
      // deno-lint-ignore no-explicit-any
      .map((x: any) => String(x.email).toLowerCase()).filter((e: string) => e !== actor);
    if (!to.length) return json({ sent: 0, reason: "no_account" });
    const { data: subs } = await admin.from("push_subs").select("endpoint,sub").in("email", to);
    if (!subs || !subs.length) return json({ sent: 0, reason: "no_subscription" });
    webpush.setVapidDetails(site || "mailto:noreply@example.com", k.public_key, k.private_key);
    const payload = JSON.stringify({ title: "Tuntutan kos: " + (CAT[c.cat] || "Kos") + " " + rm(c.amount), body: [c.byName, c.plate, c.desc].filter(Boolean).join(" · "), tag: "claim-" + jobId, url: (site || ".") + (site ? "" : "/") + "#kos" });
    let sent = 0;
    for (const s of subs) {
      try { await webpush.sendNotification(s.sub, payload, { TTL: 86400 }); sent++; }
      // deno-lint-ignore no-explicit-any
      catch (e: any) { if (e && (e.statusCode === 404 || e.statusCode === 410)) await admin.from("push_subs").delete().eq("endpoint", s.endpoint); }
    }
    return json({ sent, total: subs.length });
  }

  const { data: job } = await admin.from("jobs").select("data").eq("org", org).eq("id", jobId).maybeSingle();
  if (!job) return json({ error: "not_found" }, 404);
  const j = job.data || {};
  const { data: cfg } = await admin.from("config").select("data").eq("org", org).eq("id", "company").maybeSingle();
  // deno-lint-ignore no-explicit-any
  const drs: any[] = (cfg && cfg.data && cfg.data.drivers) || [];
  let cust = j.customerName || "";
  if (j.customerId) {
    const { data: c } = await admin.from("customers").select("data").eq("org", org).eq("id", j.customerId).maybeSingle();
    if (c && c.data && c.data.name) cust = c.data.name;
  }

  let emails: string[] = [];
  // deno-lint-ignore no-explicit-any
  let msg: any = null;
  if (body.action === "notify") {
    // Job baharu untuk pemandu
    if (!j.driverId) return json({ sent: 0, reason: "no_driver" });
    const d = drs.find((x) => x.id === j.driverId);
    if (d && d.email) emails = [String(d.email).toLowerCase()];
    else {
      const bound = new Set(drs.filter((x) => x.email).map((x) => String(x.email).toLowerCase()));
      const { data: m } = await admin.from("members").select("email").eq("org", org).eq("role", "driver");
      emails = (m || []).map((x) => String(x.email).toLowerCase()).filter((e) => !bound.has(e));
    }
    msg = { title: "Job baharu: " + (j.no || ""), body: [cust, [dmy(j.startDate), j.time].filter(Boolean).join(" · "), [j.pickup, j.dropoff].filter(Boolean).join(" → ")].filter(Boolean).join("\n"), tag: "job-" + jobId, url: (site || ".") + (site ? "" : "/") + "#tugasan" };
  } else {
    // Makluman kepada admin (dan staf dengan akses Rekod Kerja)
    const { data: m } = await admin.from("members").select("email,role,perms").eq("org", org);
    // deno-lint-ignore no-explicit-any
    emails = (m || []).filter((x: any) => x.role === "admin" || (x.role === "staff" && Array.isArray(x.perms) && x.perms.includes("kerja")))
      // deno-lint-ignore no-explicit-any
      .map((x: any) => String(x.email).toLowerCase()).filter((e: string) => e !== actor);
    const dv = drs.find((x) => x.id === (j.requestedBy || j.driverId));
    const who = (dv && (dv.name + (dv.plate ? " (" + dv.plate + ")" : ""))) || j.requestedByName || (j.do && j.do.issuer && j.do.issuer.name) || "Pemandu";
    const D = j.do || {};
    const kind = String(body.kind || "");
    if (kind === "request") msg = { title: "Job baharu dari pemandu: " + (j.no || ""), body: [who, cust, Number(j.offerPrice) > 0 ? "Tawaran " + rm(j.offerPrice) : ""].filter(Boolean).join("\n") };
    else if (kind === "accept") msg = { title: "Job diterima: " + (j.no || ""), body: [who + " terima job", cust].filter(Boolean).join("\n") };
    else if (kind === "do") msg = { title: "DO " + (D.no || "") + " ditandatangani", body: [(j.no || "") + " · " + cust, D.receiver && D.receiver.name ? "PIC: " + D.receiver.name : ""].filter(Boolean).join("\n") };
    else if (kind === "doadd") msg = { title: "DO " + (D.no || "") + ": barang ditambah", body: [who + " tambah barang", (j.no || "") + " · " + cust].filter(Boolean).join("\n") };
    else return json({ error: "bad_kind" }, 400);
    msg.tag = kind + "-" + jobId;
    msg.url = (site || ".") + (site ? "" : "/") + "#kerja";
  }
  if (!emails.length) return json({ sent: 0, reason: "no_account" });

  const { data: subs } = await admin.from("push_subs").select("endpoint,sub").in("email", emails);
  if (!subs || !subs.length) return json({ sent: 0, reason: "no_subscription" });
  webpush.setVapidDetails(site || "mailto:noreply@example.com", k.public_key, k.private_key);
  const payload = JSON.stringify(msg);
  let sent = 0;
  for (const s of subs) {
    try { await webpush.sendNotification(s.sub, payload, { TTL: 86400 }); sent++; }
    // deno-lint-ignore no-explicit-any
    catch (e: any) { if (e && (e.statusCode === 404 || e.statusCode === 410)) await admin.from("push_subs").delete().eq("endpoint", s.endpoint); }
  }
  return json({ sent, total: subs.length });
});
