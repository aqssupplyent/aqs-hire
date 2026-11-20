-- AQS Supply Hire: salin kenderaan (aset) & pemandu dari AQS ke AK12
-- Selamat dijalankan semula: rekod yang sudah ada di AK12 tidak ditindih.

-- Bahagian 1: kenderaan / aset (kecuali data contoh)
insert into public.assets (org, id, data, updated_by, updated_at)
select 'ak12', a.id, a.data, 'salin-dari-aqs', now()
from public.assets a
where a.org = 'aqs' and coalesce(a.data->>'example','') <> 'true'
on conflict (org, id) do nothing;

-- Bahagian 2: senarai pemandu (dalam tetapan syarikat)
insert into public.config (org, id, data)
values ('ak12', 'company', '{}'::jsonb)
on conflict (org, id) do nothing;

update public.config k
set data = k.data || jsonb_build_object('drivers',
      coalesce(k.data->'drivers','[]'::jsonb) || coalesce((
        select jsonb_agg(d) from jsonb_array_elements(coalesce(a.data->'drivers','[]'::jsonb)) d
        where not exists (select 1 from jsonb_array_elements(coalesce(k.data->'drivers','[]'::jsonb)) e where e->>'id' = d->>'id')
      ), '[]'::jsonb)),
    updated_at = now()
from public.config a
where k.org = 'ak12' and k.id = 'company' and a.org = 'aqs' and a.id = 'company';

-- Bahagian 3: akaun log masuk pemandu juga boleh masuk AK12
insert into public.members (email, org, name, role)
select m.email, 'ak12', m.name, 'driver'
from public.members m
where m.org = 'aqs' and m.role = 'driver'
on conflict (email, org) do nothing;

-- Semak
select (select count(*) from public.assets where org = 'ak12') as aset_ak12,
       (select jsonb_array_length(coalesce(data->'drivers','[]'::jsonb)) from public.config where org = 'ak12' and id = 'company') as pemandu_ak12,
       (select count(*) from public.members where org = 'ak12' and role = 'driver') as akaun_pemandu_ak12;
