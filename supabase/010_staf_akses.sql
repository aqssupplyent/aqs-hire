-- AQS Supply Hire: peranan "staf" dengan akses menu yang dipilih admin
-- Jalankan selepas 003, 004, 007 dan 009. Selamat dijalankan semula.

-- Bahagian 1: benarkan peranan staff + senarai akses
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid = 'public.members'::regclass and contype = 'c' loop
    execute format('alter table public.members drop constraint %I', c);
  end loop;
end $$;
alter table public.members add constraint members_role_check check (role in ('admin','driver','staff'));
alter table public.members add column if not exists perms text[] not null default '{}';

-- Bahagian 2: semakan akses (admin = semua)
create or replace function public.has_perm(o text, p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where email = public.my_email() and org = o
    and (role = 'admin' or (role = 'staff' and p = any(perms))));
$$;
grant execute on function public.has_perm(text, text) to authenticated;

-- Bahagian 3: invois, gaji, pautan DO vendor, dokumen aset ikut akses
drop policy if exists org_admin on public.invoices;
create policy org_admin on public.invoices for all to authenticated using (public.has_perm(org,'invois')) with check (public.has_perm(org,'invois'));
drop policy if exists org_admin on public.payroll;
create policy org_admin on public.payroll for all to authenticated using (public.has_perm(org,'gaji')) with check (public.has_perm(org,'gaji'));
drop policy if exists do_links_admin on public.do_links;
create policy do_links_admin on public.do_links for all to authenticated using (public.has_perm(org,'kerja')) with check (public.has_perm(org,'kerja'));
drop policy if exists docs_read on storage.objects;
drop policy if exists docs_insert on storage.objects;
drop policy if exists docs_update on storage.objects;
drop policy if exists docs_delete on storage.objects;
create policy docs_read   on storage.objects for select to authenticated using (bucket_id = 'docs' and public.has_perm(split_part(name, '/', 1), 'aset'));
create policy docs_insert on storage.objects for insert to authenticated with check (bucket_id = 'docs' and public.has_perm(split_part(name, '/', 1), 'aset'));
create policy docs_update on storage.objects for update to authenticated using (bucket_id = 'docs' and public.has_perm(split_part(name, '/', 1), 'aset')) with check (bucket_id = 'docs' and public.has_perm(split_part(name, '/', 1), 'aset'));
create policy docs_delete on storage.objects for delete to authenticated using (bucket_id = 'docs' and public.has_perm(split_part(name, '/', 1), 'aset'));
