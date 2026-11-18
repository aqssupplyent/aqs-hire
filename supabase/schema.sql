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
  'name','AQS Supply','defaultTax',8,'terms',30,
  'footer','Sila buat bayaran ke akaun bank di atas dan nyatakan no. invois sebagai rujukan.'))
on conflict (id) do nothing;

-- 4. Daftar staf. Tukar e-mel di bawah kepada e-mel anda (dan staf lain).
insert into public.staff (email, name) values
  ('EMAIL-ANDA@contoh.com', 'Pentadbir')
on conflict (email) do nothing;
-- Tambah staf kemudian:
--   insert into public.staff (email, name) values ('staf@contoh.com', 'Nama Staf');
-- Buang staf:
--   delete from public.staff where email = 'staf@contoh.com';
