-- AQS Supply Hire: peranan pemandu + DO digital
-- Jalankan SEKALI dalam Supabase → SQL Editor → New query → Run.
-- Selamat dijalankan semula.

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
