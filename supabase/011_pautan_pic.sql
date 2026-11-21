-- AQS Supply Hire: pautan tandatangan DO untuk PIC tapak (tanpa log masuk)
-- Admin / pemandu isi DO dahulu, PIC hanya isi nama, IC dan tandatangan.
-- Jalankan selepas 003. Selamat dijalankan semula.

-- Bahagian 1: jadual pautan
create table if not exists public.pic_links (
  token      text primary key,
  org        text not null,
  job_id     text not null,
  created_by text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz
);
alter table public.pic_links enable row level security;
drop policy if exists pic_links_member on public.pic_links;
create policy pic_links_member on public.pic_links for all to authenticated
  using (public.is_member(org)) with check (public.is_member(org));

-- Bahagian 2: baca DO untuk PIC
create or replace function public.pic_job(p_token text) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.pic_links%rowtype; c jsonb; j record; cu jsonb;
begin
  select * into l from public.pic_links where token = p_token;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  select id, data into j from public.jobs where org = l.org and id = l.job_id;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if coalesce(j.data->'do'->>'status','') = 'signed' then return jsonb_build_object('error','used'); end if;
  if j.data->'doDraft' is null then return jsonb_build_object('error','no_draft'); end if;
  select data into c from public.config where org = l.org and id = 'company';
  select data into cu from public.customers where org = l.org and id = j.data->>'customerId';
  return jsonb_build_object('org', l.org, 'id', j.id, 'draft', j.data->'doDraft',
    'job', jsonb_build_object('no',j.data->>'no','site',j.data->>'site','po',j.data->>'po','supervisor',j.data->>'supervisor','startDate',j.data->>'startDate','customerId',j.data->>'customerId','customerName',j.data->>'customerName','fleet',j.data->>'fleet'),
    'customer', jsonb_build_object('name',coalesce(cu->>'name', j.data->>'customerName'),'address',cu->>'address'),
    'company', jsonb_build_object('name',c->>'name','regNo',c->>'regNo','address',c->>'address','phone',c->>'phone','email',c->>'email','logo',c->>'logo','doRemarks',c->>'doRemarks','doPad',c->'doPad','doNext',c->'doNext','invTemplate',c->>'invTemplate'));
end $$;
revoke all on function public.pic_job(text) from public;
grant execute on function public.pic_job(text) to anon, authenticated;

-- Bahagian 3: PIC tandatangan
create or replace function public.pic_submit(p_token text, p_receiver jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.pic_links%rowtype; c jsonb; jd jsonb; mx int; pad int; no text; rec jsonb;
begin
  select * into l from public.pic_links where token = p_token for update;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if l.used_at is not null then return jsonb_build_object('error','used'); end if;
  if l.expires_at < now() then return jsonb_build_object('error','expired'); end if;
  select data into jd from public.jobs where org = l.org and id = l.job_id for update;
  if jd is null then return jsonb_build_object('error','not_found'); end if;
  if coalesce(jd->'do'->>'status','') = 'signed' then return jsonb_build_object('error','used'); end if;
  if jd->'doDraft' is null then return jsonb_build_object('error','no_draft'); end if;
  if coalesce(p_receiver->>'name','') = '' or coalesce(p_receiver->>'sig','') = '' then return jsonb_build_object('error','incomplete'); end if;
  if length(p_receiver::text) > 300000 then return jsonb_build_object('error','too_large'); end if;
  select data into c from public.config where org = l.org and id = 'company';
  select greatest(coalesce(nullif(c->>'doNext','')::int, case when l.org = 'aqs' then 20164 else 1 end) - 1, coalesce(max(nullif(regexp_replace(coalesce(data->'do'->>'no',''), '\D', '', 'g'), '')::int), 0)) into mx from public.jobs where org = l.org;
  pad := coalesce(nullif(c->>'doPad','')::int, 0);
  no := (mx + 1)::text;
  if length(no) < pad then no := lpad(no, pad, '0'); end if;
  rec := (jd->'doDraft') || jsonb_build_object('receiver', jsonb_build_object('name', upper(p_receiver->>'name'), 'ic', coalesce(p_receiver->>'ic',''), 'sig', p_receiver->>'sig', 'signedAt', now()),
           'no', no, 'status', 'signed', 'submittedAt', now(), 'via', 'pic_link');
  update public.jobs set data = (data - 'doDraft') || jsonb_build_object('do', rec, 'status', 'done', 'endDate', coalesce(nullif(data->>'endDate',''), rec->>'date'),
      'log', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', now(), 'by', 'PIC: ' || upper(p_receiver->>'name'), 'msg', 'DO ' || no || ' ditandatangani oleh ' || upper(p_receiver->>'name') || ' (pautan PIC)'))),
    updated_at = now(), updated_by = 'pic-link'
  where org = l.org and id = l.job_id;
  update public.pic_links set used_at = now() where token = p_token;
  return jsonb_build_object('ok', true, 'no', no);
end $$;
revoke all on function public.pic_submit(text, jsonb) from public;
grant execute on function public.pic_submit(text, jsonb) to anon, authenticated;
