begin;
-- Service-only helpers for the password-verified login migration Edge Function.
-- They are NOT callable with an APK's publishable key or ordinary user JWT.
create schema if not exists zela_sync;
revoke all on schema zela_sync from public, anon;
grant usage on schema zela_sync to service_role;
create table if not exists zela_sync.staff_login_attempts(
  email_hash text primary key,
  window_started timestamptz not null,
  attempts integer not null
);
alter table zela_sync.staff_login_attempts enable row level security;
revoke all on zela_sync.staff_login_attempts from public, anon, authenticated;
grant select,insert,update,delete on zela_sync.staff_login_attempts to service_role;

create or replace function public.prepare_legacy_staff_login(p_email text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_email text := lower(btrim(p_email));
  v_key text;
  v_count integer;
  v_user public.users%rowtype;
begin
  if v_email is null or length(v_email) not between 3 and 254 then
    return jsonb_build_object('status','invalid');
  end if;
  v_key := encode(extensions.digest(v_email,'sha256'),'hex');
  insert into zela_sync.staff_login_attempts(email_hash,window_started,attempts)
    values(v_key,now(),1)
  on conflict(email_hash) do update
    set attempts=case when staff_login_attempts.window_started < now()-interval '15 minutes'
      then 1 else staff_login_attempts.attempts+1 end,
        window_started=case when staff_login_attempts.window_started < now()-interval '15 minutes'
      then now() else staff_login_attempts.window_started end
  returning attempts into v_count;
  if v_count>5 then return jsonb_build_object('status','limited'); end if;
  select * into v_user from public.users where lower(email)=v_email;
  if not found or v_user.is_active is not true or v_user.is_approved is not true
     or coalesce(v_user.role,'') not in ('kasir','manajer','admin')
     or v_user.auth_id is not null or coalesce(v_user.password,'') !~* '^[0-9a-f]{64}$' then
    return jsonb_build_object('status','invalid');
  end if;
  return jsonb_build_object('status','ok','staff_id',v_user.id,'email',v_user.email,
    'password_hash',lower(v_user.password));
end;
$$;
revoke all on function public.prepare_legacy_staff_login(text) from public,anon,authenticated;
grant execute on function public.prepare_legacy_staff_login(text) to service_role;

create or replace function public.link_legacy_staff_auth(p_staff_id uuid,p_auth_id uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare v_count integer;
begin
  if p_auth_id is null then return false; end if;
  update public.users set auth_id=p_auth_id
    where id=p_staff_id and (auth_id is null or auth_id=p_auth_id)
      and is_active is true and is_approved is true
      and role in ('kasir','manajer','admin');
  get diagnostics v_count = row_count;
  return v_count=1;
end;
$$;
revoke all on function public.link_legacy_staff_auth(uuid,uuid) from public,anon,authenticated;
grant execute on function public.link_legacy_staff_auth(uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
