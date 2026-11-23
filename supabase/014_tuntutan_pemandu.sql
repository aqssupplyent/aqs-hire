-- AQS Supply Hire: pemandu hantar resit kos (tol, minyak, pembaikan) untuk kelulusan admin
-- Jalankan selepas 013. Selamat dijalankan semula.

-- Bahagian 1: pemandu boleh hantar dan lihat tuntutan sendiri sahaja
drop policy if exists costs_driver_insert on public.costs;
create policy costs_driver_insert on public.costs for insert to authenticated
  with check (public.is_member(org) and data->>'status' = 'pending' and lower(data->>'byEmail') = public.my_email());
drop policy if exists costs_driver_read on public.costs;
create policy costs_driver_read on public.costs for select to authenticated
  using (public.is_member(org) and lower(data->>'byEmail') = public.my_email());

-- Bahagian 2: gambar resit tuntutan (folder claims)
drop policy if exists docs_claim_insert on storage.objects;
create policy docs_claim_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'docs' and split_part(name,'/',2) = 'claims' and public.is_member(split_part(name,'/',1)));
drop policy if exists docs_claim_read on storage.objects;
create policy docs_claim_read on storage.objects for select to authenticated
  using (bucket_id = 'docs' and split_part(name,'/',2) = 'claims' and public.is_member(split_part(name,'/',1)));
