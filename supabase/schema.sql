-- AQS Supply Hire: skema pangkalan data
-- Jalankan SEKALI dalam Supabase → SQL Editor → New query → Run.
-- Selamat dijalankan semula (idempotent).

-- 1. Senarai staf yang dibenarkan guna sistem
create table if not exists public.staff (
  email text primary key,
  name  text,
  added_at timestamptz not null default now()
);
alter table public.staff enable row level security;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where lower(email) = lower(auth.jwt() ->> 'email'));
$$;
grant execute on function public.is_staff() to authenticated;

drop policy if exists staff_read on public.staff;
create policy staff_read on public.staff for select to authenticated using (public.is_staff());

-- 2. Jadual data (setiap rekod disimpan sebagai JSON dalam lajur "data")
do $$
declare t text;
begin
  foreach t in array array['customers','assets','jobs','invoices','config'] loop
    execute format('create table if not exists public.%I (
      id text primary key,
      data jsonb not null default ''{}''::jsonb,
      updated_by text,
      updated_at timestamptz not null default now()
    )', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists staff_all on public.%I', t);
    execute format('create policy staff_all on public.%I for all to authenticated using (public.is_staff()) with check (public.is_staff())', t);
    -- realtime: perubahan muncul serta-merta pada skrin staf lain
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- 3. Tetapan syarikat awal
insert into public.config (id, data) values ('company', jsonb_build_object(
  'name','AQS Supply Enterprise','defaultTax',0,'terms',15,
  'footer','This is computer generated invoice no signature required.'))
on conflict (id) do nothing;

-- 4. Daftar staf. Tukar e-mel di bawah kepada e-mel anda (dan staf lain).
insert into public.staff (email, name) values
  ('EMAIL-ANDA@contoh.com', 'Pentadbir')
on conflict (email) do nothing;
-- Tambah staf kemudian:
--   insert into public.staff (email, name) values ('staf@contoh.com', 'Nama Staf');
-- Buang staf:
--   delete from public.staff where email = 'staf@contoh.com';

-- ===== Tambahan: peranan pemandu + DO digital (sama dengan 002_pemandu_do.sql) =====

-- 1. Peranan: 'admin' (semua) atau 'driver' (tugasan & DO sahaja)
alter table public.staff add column if not exists role text not null default 'admin';
do $$ begin
  alter table public.staff add constraint staff_role_check check (role in ('admin','driver'));
exception when duplicate_object then null; end $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff
                 where lower(email) = lower(auth.jwt() ->> 'email') and role = 'admin');
$$;
grant execute on function public.is_admin() to authenticated;

-- 2. Admin boleh tambah / buang staf dari dalam sistem
drop policy if exists staff_admin on public.staff;
create policy staff_admin on public.staff for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 3. Invois: admin sahaja (pemandu tidak nampak harga)
drop policy if exists staff_all on public.invoices;
drop policy if exists admin_all on public.invoices;
create policy admin_all on public.invoices for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 4. Tetapan syarikat: semua staf boleh baca (untuk kepala DO), admin sahaja boleh ubah
drop policy if exists staff_all on public.config;
drop policy if exists config_read on public.config;
drop policy if exists config_write on public.config;
create policy config_read on public.config for select to authenticated using (public.is_staff());
create policy config_write on public.config for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ===== Tambahan: banyak syarikat (sama dengan 003_multi_syarikat.sql) =====

-- 1. Senarai syarikat
create table if not exists public.orgs (
  id         text primary key,
  name       text not null,
  created_at timestamptz not null default now()
);
insert into public.orgs (id, name) values ('aqs', 'AQS Supply Enterprise')
on conflict (id) do nothing;

-- 2. Keahlian: siapa ahli syarikat mana, dengan peranan apa
create table if not exists public.members (
  email text not null,
  org   text not null references public.orgs(id) on delete cascade,
  name  text,
  role  text not null default 'admin' check (role in ('admin','driver')),
  primary key (email, org)
);
-- staf sedia ada menjadi ahli AQS
do $$ begin
  insert into public.members (email, org, name, role)
  select lower(email), 'aqs', name, coalesce(role,'admin') from public.staff
  on conflict (email, org) do nothing;
exception when undefined_column then
  insert into public.members (email, org, name)
  select lower(email), 'aqs', name from public.staff
  on conflict (email, org) do nothing;
end $$;

-- 3. Fungsi semakan akses
create or replace function public.my_email() returns text
language sql stable as $$ select lower(auth.jwt() ->> 'email') $$;

create or replace function public.is_member(o text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where email = public.my_email() and org = o);
$$;
create or replace function public.is_org_admin(o text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where email = public.my_email() and org = o and role = 'admin');
$$;
create or replace function public.is_any_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where email = public.my_email() and role = 'admin');
$$;
grant execute on function public.my_email(), public.is_member(text), public.is_org_admin(text), public.is_any_admin() to authenticated;

-- Admin mana-mana syarikat boleh mencipta syarikat baharu (dan menjadi admin syarikat itu)
create or replace function public.create_org(p_id text, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_any_admin() then raise exception 'not allowed'; end if;
  if p_id !~ '^[a-z0-9][a-z0-9-]{1,30}$' then raise exception 'bad id'; end if;
  insert into public.orgs (id, name) values (p_id, p_name);
  insert into public.members (email, org, name, role) values (public.my_email(), p_id, null, 'admin');
end $$;
grant execute on function public.create_org(text, text) to authenticated;

-- 4. Setiap jadual data ditanda dengan syarikat
do $$
declare t text; pol record;
begin
  foreach t in array array['customers','assets','jobs','invoices','config'] loop
    execute format('alter table public.%I add column if not exists org text not null default ''aqs''', t);
    execute format('alter table public.%I drop constraint if exists %I', t, t || '_pkey');
    execute format('alter table public.%I add primary key (org, id)', t);
    for pol in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', pol.policyname, t);
    end loop;
  end loop;
end $$;

-- 5. Polisi: hanya ahli syarikat itu nampak datanya
create policy org_rw on public.customers for all to authenticated using (public.is_member(org)) with check (public.is_member(org));
create policy org_rw on public.assets    for all to authenticated using (public.is_member(org)) with check (public.is_member(org));
create policy org_rw on public.jobs      for all to authenticated using (public.is_member(org)) with check (public.is_member(org));
-- invois: admin syarikat sahaja
create policy org_admin on public.invoices for all to authenticated using (public.is_org_admin(org)) with check (public.is_org_admin(org));
-- tetapan: ahli boleh baca, admin boleh ubah
create policy org_read  on public.config for select to authenticated using (public.is_member(org));
create policy org_write on public.config for all    to authenticated using (public.is_org_admin(org)) with check (public.is_org_admin(org));

alter table public.orgs    enable row level security;
alter table public.members enable row level security;
drop policy if exists orgs_read   on public.orgs;
drop policy if exists orgs_update on public.orgs;
create policy orgs_read   on public.orgs for select to authenticated using (public.is_member(id));
create policy orgs_update on public.orgs for update to authenticated using (public.is_org_admin(id)) with check (public.is_org_admin(id));

drop policy if exists members_read  on public.members;
drop policy if exists members_admin on public.members;
create policy members_read  on public.members for select to authenticated using (email = public.my_email() or public.is_member(org));
create policy members_admin on public.members for all    to authenticated using (public.is_org_admin(org)) with check (public.is_org_admin(org));

-- Tambah ahli secara manual (contoh):
--   insert into public.members (email, org, name, role) values ('staf@contoh.com', 'aqs', 'NAMA STAF', 'admin');

-- ===== Tambahan: pautan DO vendor (sama dengan 004_do_vendor.sql) =====

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

-- ===== Tambahan: kata laluan pemandu (sama dengan 005_kata_laluan_pemandu.sql) =====
create or replace function public.admin_set_password(p_email text, p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare e text := lower(trim(p_email)); uid uuid;
begin
  if length(coalesce(p_password,'')) < 8 then return jsonb_build_object('error','short'); end if;
  if not exists (select 1 from public.members m where m.email = e and public.is_org_admin(m.org)) then
    return jsonb_build_object('error','not_allowed'); end if;
  if exists (select 1 from public.members m where m.email = e and m.role = 'admin') then
    return jsonb_build_object('error','is_admin'); end if;
  select id into uid from auth.users where lower(email) = e;
  if uid is null then return jsonb_build_object('error','no_user'); end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = uid;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_set_password(text, text) from public;
grant execute on function public.admin_set_password(text, text) to authenticated;

-- ===== Tambahan: satu pautan vendor untuk beberapa job (sama dengan 006) =====
-- Bahagian 1: senarai job dalam satu pautan
alter table public.do_links add column if not exists job_ids text[];

-- Bahagian 2: baca semua job dalam pautan (tanpa log masuk)
create or replace function public.vendor_jobs(p_token text) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.do_links%rowtype; c jsonb; ids text[]; arr jsonb := '[]'::jsonb; j record; cu jsonb;
begin
  select * into l from public.do_links where token = p_token;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  ids := coalesce(l.job_ids, array[l.job_id]);
  select data into c from public.config where org = l.org and id = 'company';
  for j in select id, data from public.jobs where org = l.org and id = any(ids) order by data->>'no' loop
    select data into cu from public.customers where org = l.org and id = j.data->>'customerId';
    arr := arr || jsonb_build_array(jsonb_build_object('id', j.id,
      'done', coalesce(j.data->'do'->>'status','') = 'signed', 'doNo', j.data->'do'->>'no',
      'job', jsonb_build_object('no',j.data->>'no','site',j.data->>'site','po',j.data->>'po','pickup',j.data->>'pickup','dropoff',j.data->>'dropoff','load',j.data->>'load','time',j.data->>'time','supervisor',j.data->>'supervisor','startDate',j.data->>'startDate','customerId',j.data->>'customerId','vehicle',j.data->>'vehicle','vendorName',j.data->>'vendorName','vendorPlate',j.data->>'vendorPlate','vendorDriver',j.data->>'vendorDriver','lines',j.data->'lines','status',j.data->>'status'),
      'customer', jsonb_build_object('name',cu->>'name','address',cu->>'address')));
  end loop;
  return jsonb_build_object('org', l.org, 'jobs', arr,
    'company', jsonb_build_object('name',c->>'name','regNo',c->>'regNo','address',c->>'address','phone',c->>'phone','email',c->>'email','logo',c->>'logo','doRemarks',c->>'doRemarks','doPad',c->'doPad','doNext',c->'doNext','invTemplate',c->>'invTemplate'));
end $$;
revoke all on function public.vendor_jobs(text) from public;
grant execute on function public.vendor_jobs(text) to anon, authenticated;

-- Bahagian 3: hantar DO untuk satu job dalam pautan (tanpa log masuk)
create or replace function public.vendor_submit_job_do(p_token text, p_job_id text, p_do jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.do_links%rowtype; c jsonb; ids text[]; mx int; pad int; no text; rec jsonb;
begin
  select * into l from public.do_links where token = p_token for update;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  ids := coalesce(l.job_ids, array[l.job_id]);
  if not (p_job_id = any(ids)) then return jsonb_build_object('error','not_found'); end if;
  if exists (select 1 from public.jobs where org = l.org and id = p_job_id and coalesce(data->'do'->>'status','') = 'signed') then return jsonb_build_object('error','already'); end if;
  if coalesce(p_do->'receiver'->>'name','') = '' or coalesce(p_do->'receiver'->>'sig','') = '' or coalesce(p_do->'issuer'->>'sig','') = '' then return jsonb_build_object('error','incomplete'); end if;
  if length(p_do::text) > 400000 then return jsonb_build_object('error','too_large'); end if;
  select data into c from public.config where org = l.org and id = 'company';
  select greatest(coalesce(nullif(c->>'doNext','')::int, case when l.org = 'aqs' then 20164 else 1 end) - 1, coalesce(max(nullif(regexp_replace(coalesce(data->'do'->>'no',''), '\D', '', 'g'), '')::int), 0)) into mx from public.jobs where org = l.org;
  pad := coalesce(nullif(c->>'doPad','')::int, 0);
  no := (mx + 1)::text;
  if length(no) < pad then no := lpad(no, pad, '0'); end if;
  rec := p_do || jsonb_build_object('no', no, 'status', 'signed', 'submittedAt', now(), 'via', 'vendor_link');
  update public.jobs set data = data || jsonb_build_object('do', rec, 'status', 'done', 'endDate', coalesce(nullif(data->>'endDate',''), rec->>'date'),
      'log', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', now(), 'by', 'Vendor: ' || coalesce(p_do->'issuer'->>'name',''), 'msg', 'DO ' || no || ' ditandatangani oleh ' || (p_do->'receiver'->>'name') || ' (pautan vendor)'))),
    updated_at = now(), updated_by = 'vendor-link'
  where org = l.org and id = p_job_id;
  if not exists (select 1 from public.jobs where org = l.org and id = any(ids) and coalesce(data->'do'->>'status','') <> 'signed') then
    update public.do_links set used_at = now() where token = p_token;
  end if;
  return jsonb_build_object('ok', true, 'no', no);
end $$;
revoke all on function public.vendor_submit_job_do(text, text, jsonb) from public;
grant execute on function public.vendor_submit_job_do(text, text, jsonb) to anon, authenticated;
