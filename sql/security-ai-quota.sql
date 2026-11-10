create table if not exists zela_sync.ai_chat_usage(
  owner_id uuid not null, usage_date date not null,
  used integer not null default 0, window_start timestamptz not null,
  window_used integer not null default 0,
  primary key(owner_id,usage_date)
);
alter table zela_sync.ai_chat_usage enable row level security;
revoke all on zela_sync.ai_chat_usage from public,anon,authenticated;
create or replace function zela_sync.reserve_ai_chat(p_auth_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a public.users%rowtype; v zela_sync.ai_chat_usage%rowtype; d date:=(now() at time zone 'Asia/Jakarta')::date;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Service only' using errcode='42501'; end if;
  select * into a from public.users where auth_id=p_auth_id and is_active is true and is_approved is true;
  if not found or a.owner_id is null or a.role not in ('owner','admin','manajer','superadmin') then
    return jsonb_build_object('allowed',false,'status',403);
  end if;
  insert into zela_sync.ai_chat_usage(owner_id,usage_date,window_start)
    values(a.owner_id,d,now()) on conflict do nothing;
  select * into v from zela_sync.ai_chat_usage where owner_id=a.owner_id and usage_date=d for update;
  if v.window_start<=now()-interval '1 minute' then v.window_used:=0; v.window_start:=now(); end if;
  if v.used>=200 or v.window_used>=10 then
    return jsonb_build_object('allowed',false,'status',429);
  end if;
  update zela_sync.ai_chat_usage set used=v.used+1,window_used=v.window_used+1,window_start=v.window_start
    where owner_id=a.owner_id and usage_date=d;
  return jsonb_build_object('allowed',true,'status',200);
end;
$$;
revoke all on function zela_sync.reserve_ai_chat(uuid) from public,anon,authenticated;
grant execute on function zela_sync.reserve_ai_chat(uuid) to service_role;
create or replace function public.reserve_ai_chat(p_auth_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select zela_sync.reserve_ai_chat(p_auth_id);
$$;
revoke all on function public.reserve_ai_chat(uuid) from public,anon,authenticated;
grant execute on function public.reserve_ai_chat(uuid) to service_role;
notify pgrst,'reload schema';
