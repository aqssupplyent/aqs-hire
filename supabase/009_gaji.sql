-- AQS Supply Hire: data gaji pemandu (gaji pokok, elaun, klinik, potongan, perubatan, pinjaman). Admin sahaja.
-- Selamat dijalankan semula.
create table if not exists public.payroll (
  org text not null references public.orgs(id) on delete cascade,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (org, id)
);
alter table public.payroll enable row level security;
drop policy if exists org_admin on public.payroll;
create policy org_admin on public.payroll for all to authenticated using (public.is_org_admin(org)) with check (public.is_org_admin(org));
