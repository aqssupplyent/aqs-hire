-- AQS Supply Hire: kos kenderaan (minyak, tol, pembaikan, insurans, roadtax, Puspakom, dll)
-- Jalankan selepas 010. Selamat dijalankan semula.

-- Bahagian 1: jadual kos
create table if not exists public.costs (
  org        text not null references public.orgs(id) on delete cascade,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_by text,
  updated_at timestamptz not null default now(),
  primary key (org, id)
);
alter table public.costs enable row level security;
drop policy if exists costs_perm on public.costs;
create policy costs_perm on public.costs for all to authenticated
  using (public.has_perm(org,'kos')) with check (public.has_perm(org,'kos'));

-- Bahagian 2: resit kos boleh dimuat naik (folder dokumen yang sama)
drop policy if exists docs_read on storage.objects;
drop policy if exists docs_insert on storage.objects;
drop policy if exists docs_update on storage.objects;
drop policy if exists docs_delete on storage.objects;
create policy docs_read on storage.objects for select to authenticated using (bucket_id='docs' and (public.has_perm(split_part(name,'/',1),'aset') or public.has_perm(split_part(name,'/',1),'kos')));
create policy docs_insert on storage.objects for insert to authenticated with check (bucket_id='docs' and (public.has_perm(split_part(name,'/',1),'aset') or public.has_perm(split_part(name,'/',1),'kos')));
create policy docs_update on storage.objects for update to authenticated using (bucket_id='docs' and (public.has_perm(split_part(name,'/',1),'aset') or public.has_perm(split_part(name,'/',1),'kos'))) with check (bucket_id='docs' and (public.has_perm(split_part(name,'/',1),'aset') or public.has_perm(split_part(name,'/',1),'kos')));
create policy docs_delete on storage.objects for delete to authenticated using (bucket_id='docs' and (public.has_perm(split_part(name,'/',1),'aset') or public.has_perm(split_part(name,'/',1),'kos')));
