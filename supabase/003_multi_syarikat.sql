-- AQS Supply Hire: banyak syarikat dalam satu sistem
-- Jalankan SEKALI dalam Supabase → SQL Editor → New query → Run.
-- Selamat dijalankan semula. Data sedia ada dipindahkan ke syarikat 'aqs'.

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
