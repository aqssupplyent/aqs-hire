-- AQS Supply Hire: admin menetapkan kata laluan akaun pemandu dari sistem
-- Jalankan SEKALI dalam Supabase → SQL Editor → Run (selepas 003). Selamat dijalankan semula.
create or replace function public.admin_set_password(p_email text, p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare e text := lower(trim(p_email)); uid uuid;
begin
  if length(coalesce(p_password,'')) < 8 then return jsonb_build_object('error','short'); end if;
  if not exists (select 1 from public.members m where m.email = e and public.is_org_admin(m.org)) then
    return jsonb_build_object('error','not_allowed'); end if;
  if exists (select 1 from public.members m where m.email = e and m.role = 'admin') then
    return jsonb_build_object('error','is_admin'); end if;
  select id into uid from auth.users where lower(email) = e;
  if uid is null then return jsonb_build_object('error','no_user'); end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = uid;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_set_password(text, text) from public;
grant execute on function public.admin_set_password(text, text) to authenticated;
