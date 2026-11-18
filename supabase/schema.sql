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
