-- AQS Supply Hire: notifikasi job kepada pemandu (Web Push)
-- Jalankan selepas 003. Selamat dijalankan semula.

-- Bahagian 1: langganan notifikasi setiap telefon
create table if not exists public.push_subs (
  endpoint   text primary key,
  email      text not null,
  org        text not null,
  sub        jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.push_subs enable row level security;
drop policy if exists push_subs_own on public.push_subs;
create policy push_subs_own on public.push_subs for all to authenticated
  using (email = public.my_email()) with check (email = public.my_email() and public.is_member(org));

-- Bahagian 2: kunci notifikasi (hanya fungsi pelayan boleh baca)
create table if not exists public.push_keys (
  id          int primary key default 1,
  public_key  text not null,
  private_key text not null
);
alter table public.push_keys enable row level security;
