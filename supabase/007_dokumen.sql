-- AQS Supply Hire: storan salinan dokumen kenderaan & pemandu (peribadi, admin sahaja)
-- Jalankan selepas 003. Selamat dijalankan semula.
insert into storage.buckets (id, name, public) values ('docs', 'docs', false) on conflict (id) do nothing;
drop policy if exists docs_read on storage.objects;
drop policy if exists docs_insert on storage.objects;
drop policy if exists docs_update on storage.objects;
drop policy if exists docs_delete on storage.objects;
create policy docs_read   on storage.objects for select to authenticated using (bucket_id = 'docs' and public.is_org_admin(split_part(name, '/', 1)));
create policy docs_insert on storage.objects for insert to authenticated with check (bucket_id = 'docs' and public.is_org_admin(split_part(name, '/', 1)));
create policy docs_update on storage.objects for update to authenticated using (bucket_id = 'docs' and public.is_org_admin(split_part(name, '/', 1))) with check (bucket_id = 'docs' and public.is_org_admin(split_part(name, '/', 1)));
create policy docs_delete on storage.objects for delete to authenticated using (bucket_id = 'docs' and public.is_org_admin(split_part(name, '/', 1)));
