-- AQS Supply Hire: satu pautan DO vendor untuk beberapa job (lori / pemandu berbeza)
-- Jalankan selepas 004. Selamat dijalankan semula. Pautan lama tetap berfungsi.

-- Bahagian 1: senarai job dalam satu pautan
alter table public.do_links add column if not exists job_ids text[];

-- Bahagian 2: baca semua job dalam pautan (tanpa log masuk)
create or replace function public.vendor_jobs(p_token text) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.do_links%rowtype; c jsonb; ids text[]; arr jsonb := '[]'::jsonb; j record; cu jsonb;
begin
  select * into l from public.do_links where token = p_token;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  ids := coalesce(l.job_ids, array[l.job_id]);
  select data into c from public.config where org = l.org and id = 'company';
  for j in select id, data from public.jobs where org = l.org and id = any(ids) order by data->>'no' loop
    select data into cu from public.customers where org = l.org and id = j.data->>'customerId';
    arr := arr || jsonb_build_array(jsonb_build_object('id', j.id,
      'done', coalesce(j.data->'do'->>'status','') = 'signed', 'doNo', j.data->'do'->>'no',
      'job', jsonb_build_object('no',j.data->>'no','site',j.data->>'site','po',j.data->>'po','pickup',j.data->>'pickup','dropoff',j.data->>'dropoff','load',j.data->>'load','time',j.data->>'time','supervisor',j.data->>'supervisor','startDate',j.data->>'startDate','customerId',j.data->>'customerId','vehicle',j.data->>'vehicle','vendorName',j.data->>'vendorName','vendorPlate',j.data->>'vendorPlate','vendorDriver',j.data->>'vendorDriver','lines',j.data->'lines','status',j.data->>'status'),
      'customer', jsonb_build_object('name',cu->>'name','address',cu->>'address')));
  end loop;
  return jsonb_build_object('org', l.org, 'jobs', arr,
    'company', jsonb_build_object('name',c->>'name','regNo',c->>'regNo','address',c->>'address','phone',c->>'phone','email',c->>'email','logo',c->>'logo','doRemarks',c->>'doRemarks','doPad',c->'doPad','doNext',c->'doNext','invTemplate',c->>'invTemplate'));
end $$;
revoke all on function public.vendor_jobs(text) from public;
grant execute on function public.vendor_jobs(text) to anon, authenticated;

-- Bahagian 3: hantar DO untuk satu job dalam pautan (tanpa log masuk)
create or replace function public.vendor_submit_job_do(p_token text, p_job_id text, p_do jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.do_links%rowtype; c jsonb; ids text[]; mx int; pad int; no text; rec jsonb;
begin
  select * into l from public.do_links where token = p_token for update;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  ids := coalesce(l.job_ids, array[l.job_id]);
  if not (p_job_id = any(ids)) then return jsonb_build_object('error','not_found'); end if;
  if exists (select 1 from public.jobs where org = l.org and id = p_job_id and coalesce(data->'do'->>'status','') = 'signed') then return jsonb_build_object('error','already'); end if;
  if coalesce(p_do->'receiver'->>'name','') = '' or coalesce(p_do->'receiver'->>'sig','') = '' or coalesce(p_do->'issuer'->>'sig','') = '' then return jsonb_build_object('error','incomplete'); end if;
  if length(p_do::text) > 400000 then return jsonb_build_object('error','too_large'); end if;
  select data into c from public.config where org = l.org and id = 'company';
  select greatest(coalesce(nullif(c->>'doNext','')::int, case when l.org = 'aqs' then 20164 else 1 end) - 1, coalesce(max(nullif(regexp_replace(coalesce(data->'do'->>'no',''), '\D', '', 'g'), '')::int), 0)) into mx from public.jobs where org = l.org;
  pad := coalesce(nullif(c->>'doPad','')::int, 0);
  no := (mx + 1)::text;
  if length(no) < pad then no := lpad(no, pad, '0'); end if;
  rec := p_do || jsonb_build_object('no', no, 'status', 'signed', 'submittedAt', now(), 'via', 'vendor_link');
  update public.jobs set data = data || jsonb_build_object('do', rec, 'status', 'done', 'endDate', coalesce(nullif(data->>'endDate',''), rec->>'date'),
      'log', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', now(), 'by', 'Vendor: ' || coalesce(p_do->'issuer'->>'name',''), 'msg', 'DO ' || no || ' ditandatangani oleh ' || (p_do->'receiver'->>'name') || ' (pautan vendor)'))),
    updated_at = now(), updated_by = 'vendor-link'
  where org = l.org and id = p_job_id;
  if not exists (select 1 from public.jobs where org = l.org and id = any(ids) and coalesce(data->'do'->>'status','') <> 'signed') then
    update public.do_links set used_at = now() where token = p_token;
  end if;
  return jsonb_build_object('ok', true, 'no', no);
end $$;
revoke all on function public.vendor_submit_job_do(text, text, jsonb) from public;
grant execute on function public.vendor_submit_job_do(text, text, jsonb) to anon, authenticated;
