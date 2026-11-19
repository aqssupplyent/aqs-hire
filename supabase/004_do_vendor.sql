-- AQS Supply Hire: pautan DO sekali guna untuk pemandu vendor
-- Jalankan SEKALI dalam Supabase → SQL Editor → New query → Run (selepas 003).
-- Selamat dijalankan semula.

create table if not exists public.do_links (
  token      text primary key,
  org        text not null,
  job_id     text not null,
  created_by text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz
);
alter table public.do_links enable row level security;
drop policy if exists do_links_admin on public.do_links;
create policy do_links_admin on public.do_links for all to authenticated
  using (public.is_org_admin(org)) with check (public.is_org_admin(org));

-- Baca butiran job untuk satu pautan (tanpa log masuk)
create or replace function public.vendor_job(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.do_links%rowtype; j jsonb; c jsonb; cu jsonb;
begin
  select * into l from public.do_links where token = p_token;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  select data into j from public.jobs where org = l.org and id = l.job_id;
  if j is null then return jsonb_build_object('error','not_found'); end if;
  select data into c from public.config where org = l.org and id = 'company';
  select data into cu from public.customers where org = l.org and id = j->>'customerId';
  return jsonb_build_object(
    'org', l.org, 'jobId', l.job_id, 'expires', l.expires_at,
    'job', jsonb_build_object('no', j->>'no', 'site', j->>'site', 'po', j->>'po', 'pickup', j->>'pickup',
      'dropoff', j->>'dropoff', 'load', j->>'load', 'time', j->>'time', 'supervisor', j->>'supervisor',
      'startDate', j->>'startDate', 'customerId', j->>'customerId', 'vehicle', j->>'vehicle',
      'vendorName', j->>'vendorName', 'vendorPlate', j->>'vendorPlate', 'vendorDriver', j->>'vendorDriver',
      'lines', j->'lines', 'status', j->>'status'),
    'customer', jsonb_build_object('name', cu->>'name', 'address', cu->>'address'),
    'company', jsonb_build_object('name', c->>'name', 'regNo', c->>'regNo', 'address', c->>'address',
      'phone', c->>'phone', 'email', c->>'email', 'logo', c->>'logo', 'doRemarks', c->>'doRemarks',
      'doPad', c->'doPad', 'doNext', c->'doNext', 'invTemplate', c->>'invTemplate'));
end $$;

-- Hantar DO yang ditandatangani untuk satu pautan (tanpa log masuk)
create or replace function public.vendor_submit_do(p_token text, p_do jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.do_links%rowtype; c jsonb; mx int; pad int; no text; rec jsonb;
begin
  select * into l from public.do_links where token = p_token for update;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  if coalesce(p_do->'receiver'->>'name','') = '' or coalesce(p_do->'receiver'->>'sig','') = ''
     or coalesce(p_do->'issuer'->>'sig','') = '' then
    return jsonb_build_object('error','incomplete');
  end if;
  if length(p_do::text) > 400000 then return jsonb_build_object('error','too_large'); end if;
  select data into c from public.config where org = l.org and id = 'company';
  select greatest(coalesce(nullif(c->>'doNext','')::int, case when l.org = 'aqs' then 20164 else 1 end) - 1,
                  coalesce(max(nullif(regexp_replace(coalesce(data->'do'->>'no',''), '\D', '', 'g'), '')::int), 0))
    into mx from public.jobs where org = l.org;
  pad := coalesce(nullif(c->>'doPad','')::int, 0);
  no := (mx + 1)::text;
  if length(no) < pad then no := lpad(no, pad, '0'); end if;
  rec := p_do || jsonb_build_object('no', no, 'status', 'signed', 'submittedAt', now(), 'via', 'vendor_link');
  update public.jobs set
    data = data || jsonb_build_object(
      'do', rec, 'status', 'done',
      'endDate', coalesce(nullif(data->>'endDate',''), rec->>'date'),
      'log', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object(
        't', now(), 'by', 'Vendor: ' || coalesce(p_do->'issuer'->>'name',''),
        'msg', 'DO ' || no || ' ditandatangani oleh ' || (p_do->'receiver'->>'name') || ' (pautan vendor)'))),
    updated_at = now(), updated_by = 'vendor-link'
  where org = l.org and id = l.job_id;
  update public.do_links set used_at = now() where token = p_token;
  return jsonb_build_object('ok', true, 'no', no);
end $$;

revoke all on function public.vendor_job(text) from public;
revoke all on function public.vendor_submit_do(text, jsonb) from public;
grant execute on function public.vendor_job(text) to anon, authenticated;
grant execute on function public.vendor_submit_do(text, jsonb) to anon, authenticated;
