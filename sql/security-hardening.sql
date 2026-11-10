-- Reviewed against the DB Kasir Sg catalog. No business rows are deleted.
-- Run atomically; verify with test/security_hardening.test.mjs before deployment.
create schema if not exists zela_sync;
revoke all on schema zela_sync from public, anon;
grant usage on schema zela_sync to authenticated, service_role;

create or replace function zela_sync.actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('uid',u.auth_id,'owner',u.owner_id,'branch',u.branch_id,
       'role',u.role,'name',u.name,'email',u.email,'id',u.id)
     from public.users u where u.auth_id=auth.uid() and u.is_active is true
       and u.is_approved is true and u.role in ('kasir','manajer','admin','owner','superadmin') limit 1),
    (select jsonb_build_object('uid',o.auth_id,'owner',o.id,'role','owner',
       'name',o.name,'email',o.email) from public.owners o
     where o.auth_id=auth.uid() and o.is_active is true limit 1)
  );
$$;
revoke all on function zela_sync.actor() from public,anon;
grant execute on function zela_sync.actor() to authenticated,service_role;

create or replace function zela_sync.can_access_branch(p_branch uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare a jsonb := zela_sync.actor(); v_owner uuid;
begin
  if a is null then return false; end if;
  select owner_id into v_owner from public.branches where id=p_branch and is_active is true;
  return coalesce(v_owner is not null and ((a->>'role')='superadmin' or
    ((a->>'owner')=v_owner::text and ((a->>'role') in ('owner','admin','manajer')
      or (a->>'branch')=p_branch::text))),false);
end;
$$;
revoke all on function zela_sync.can_access_branch(uuid) from public,anon;
grant execute on function zela_sync.can_access_branch(uuid) to authenticated,service_role;

create or replace function zela_sync.guard_user_changes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare a jsonb; before_row jsonb; after_row jsonb; target_owner uuid; target_role text;
begin
  if auth.role()='service_role' or (auth.uid() is null and session_user in ('postgres','supabase_admin')) then
    if TG_OP='DELETE' then return OLD; else return NEW; end if;
  end if;
  a := zela_sync.actor();
  if a is null then raise exception 'Akun tidak aktif' using errcode='42501'; end if;
  if a->>'role'='superadmin' then
    if TG_OP='DELETE' then return OLD; else return NEW; end if;
  end if;
  if TG_OP='UPDATE' then
    before_row:=to_jsonb(OLD); after_row:=to_jsonb(NEW);
    if OLD.auth_id=auth.uid() then
      -- A PIN/profile edit must never change role, identity, approval or tenancy.
      if (before_row-array['name','pin_hash','wa_number']) is distinct from
         (after_row-array['name','pin_hash','wa_number']) then
        raise exception 'Perubahan hak akses akun sendiri ditolak' using errcode='42501';
      end if;
      return NEW;
    end if;
    if OLD.id is distinct from NEW.id or OLD.auth_id is distinct from NEW.auth_id
       or OLD.owner_id is distinct from NEW.owner_id or OLD.created_at is distinct from NEW.created_at then
      raise exception 'Identitas akun tidak dapat dipindahkan' using errcode='42501';
    end if;
  end if;
  if TG_OP='DELETE' then target_owner:=OLD.owner_id; target_role:=OLD.role;
  else target_owner:=NEW.owner_id; target_role:=NEW.role; end if;
  if a->>'owner' is distinct from target_owner::text or
     (a->>'role') not in ('owner','admin','manajer') or
     target_role not in ('kasir','manajer','admin') or
     ((a->>'role')='admin' and target_role='admin') or
     ((a->>'role')='manajer' and target_role<>'kasir') then
    raise exception 'Tidak berhak mengelola akun ini' using errcode='42501';
  end if;
  if TG_OP='UPDATE' and (OLD.role not in ('kasir','manajer','admin') or
      ((a->>'role')='admin' and OLD.role='admin') or
      ((a->>'role')='manajer' and OLD.role<>'kasir')) then
    raise exception 'Tidak berhak mengubah pengelola' using errcode='42501';
  end if;
  if TG_OP<>'DELETE' and NEW.branch_id is not null and not exists(
    select 1 from public.branches where id=NEW.branch_id and owner_id=target_owner) then
    raise exception 'Cabang akun tidak sesuai' using errcode='42501';
  end if;
  if TG_OP='DELETE' then return OLD; else return NEW; end if;
end;
$$;
revoke all on function zela_sync.guard_user_changes() from public,anon,authenticated;
drop trigger if exists zela_guard_user_changes on public.users;
create trigger zela_guard_user_changes before insert or update or delete on public.users
for each row execute function zela_sync.guard_user_changes();

-- Restrictive policies protect against other permissive policies, including
-- the former OR status IN ('paid','completed') predicate.
drop policy if exists orders_read_policy on public.orders;
create policy orders_read_policy on public.orders for select to authenticated
using (zela_sync.can_access_branch(branch_id));
drop policy if exists zela_orders_tenant_boundary on public.orders;
create policy zela_orders_tenant_boundary on public.orders as restrictive for all to authenticated
using (zela_sync.can_access_branch(branch_id)) with check (zela_sync.can_access_branch(branch_id));
drop policy if exists zela_stock_tenant_boundary on public.menu_stock;
create policy zela_stock_tenant_boundary on public.menu_stock as restrictive for all to authenticated
using (zela_sync.can_access_branch(branch_id)) with check (zela_sync.can_access_branch(branch_id));
drop policy if exists zela_user_read_scope on public.users;
create policy zela_user_read_scope on public.users as restrictive for select to authenticated
using (auth_id=auth.uid() or zela_sync.actor()->>'role'='superadmin' or
  (owner_id=(zela_sync.actor()->>'owner')::uuid and
   zela_sync.actor()->>'role' in ('owner','admin','manajer')));
drop policy if exists allow_anon_read_subscription on public.subscriptions;
drop policy if exists menu_stock_read_anon on public.menu_stock;
do $$ declare t text; begin
  foreach t in array array['orders','subscriptions','menu_stock','users','owners'] loop
    execute format('drop policy if exists zela_deny_anonymous on public.%I',t);
    execute format('create policy zela_deny_anonymous on public.%I as restrictive for all to anon using(false) with check(false)',t);
    execute format('revoke all on public.%I from anon',t);
  end loop;
end $$;
drop policy if exists zela_subscription_read_scope on public.subscriptions;
create policy zela_subscription_read_scope on public.subscriptions as restrictive for select to authenticated
using (owner_id=(zela_sync.actor()->>'owner')::uuid or zela_sync.actor()->>'role'='superadmin');
-- Normal users may read their plan; only a provisioned superadmin may write
-- directly. SECURITY DEFINER purchase/deduction functions continue to work.
drop policy if exists zela_subscription_update_scope on public.subscriptions;
create policy zela_subscription_update_scope on public.subscriptions as restrictive for update to authenticated
using (zela_sync.actor()->>'role'='superadmin') with check (zela_sync.actor()->>'role'='superadmin');
drop policy if exists zela_subscription_insert_scope on public.subscriptions;
create policy zela_subscription_insert_scope on public.subscriptions as restrictive for insert to authenticated
with check (zela_sync.actor()->>'role'='superadmin');
drop policy if exists zela_subscription_delete_scope on public.subscriptions;
create policy zela_subscription_delete_scope on public.subscriptions as restrictive for delete to authenticated
using (zela_sync.actor()->>'role'='superadmin');

create or replace function public.table_search(p_table_name text,p_search text,p_limit integer default 50)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare projection text; predicate text; result jsonb; a jsonb:=zela_sync.actor();
begin
  if a is null then raise exception 'Login diperlukan' using errcode='42501'; end if;
  if length(coalesce(p_search,''))>200 or p_limit is null or p_limit not between 1 and 100 then
    raise exception 'Batas pencarian tidak valid' using errcode='22023'; end if;
  case p_table_name
    when 'orders' then projection:='id,order_number,branch_id,status,total,created_at';
    when 'menu_items' then projection:='id,name,branch_id,price,is_available';
    when 'restaurant_tables' then projection:='id,name,branch_id,zone,capacity,status';
    when 'branches' then projection:='id,name,owner_id,is_active';
    when 'users' then projection:='id,name,email,role,branch_id,owner_id,is_active';
    else raise exception 'Tabel tidak tersedia untuk pencarian' using errcode='42501';
  end case;
  if p_table_name='branches' then predicate:='zela_sync.can_access_branch(t.id)';
  elsif p_table_name='users' then
    if (a->>'role') not in ('owner','admin','manajer','superadmin') then
      raise exception 'Tidak berhak mencari akun' using errcode='42501'; end if;
    predicate:='(t.owner_id=$3::uuid or $4=''superadmin'')';
  else predicate:='zela_sync.can_access_branch(t.branch_id)'; end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) from
    (select %s from public.%I t where %s and to_jsonb(t)::text ilike $1 limit $2) r',
    projection,p_table_name,predicate)
  into result using '%'||coalesce(p_search,'')||'%',p_limit,a->>'owner',a->>'role';
  return result;
end;
$$;
revoke all on function public.table_search(text,text,integer) from public,anon;
grant execute on function public.table_search(text,text,integer) to authenticated,service_role;

-- Helpers used for privilege checks must not trust a client-side email match.
create or replace function public._check_is_owner_or_sa(p_owner_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(zela_sync.actor()->>'role'='superadmin' or
    (zela_sync.actor()->>'role'='owner' and zela_sync.actor()->>'owner'=p_owner_id::text),false);
$$;
-- Provisioning a superadmin is a server administration operation, never login.
revoke all on function public.setup_superadmin(text,text) from public,anon,authenticated;
revoke all on function public.setup_superadmin(uuid,text) from public,anon,authenticated;
grant execute on function public.setup_superadmin(text,text) to service_role;
grant execute on function public.setup_superadmin(uuid,text) to service_role;

-- There is no legitimate unauthenticated financial/admin/stock RPC caller.
-- Public lead submission remains available. Authenticated grants are retained;
-- bots must use a server credential, never a service key embedded in the APK.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and p.proname<>'submit_lead'
  loop
    if has_function_privilege('authenticated',f.signature::oid,'EXECUTE') then
      execute format('grant execute on function %s to authenticated',f.signature);
    end if;
    grant usage on schema public to service_role;
    execute format('grant execute on function %s to service_role',f.signature);
    execute format('revoke execute on function %s from public,anon',f.signature);
  end loop;
  -- Pin the resolution path on existing legacy definers that use unqualified
  -- public relations. Do not set an empty path and break their dependencies.
  for f in select p.oid::regprocedure as signature from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and not exists(select 1 from unnest(coalesce(p.proconfig,array[]::text[])) c where c like 'search_path=%')
  loop
    execute format('alter function %s set search_path = pg_catalog, public, extensions, pg_temp',f.signature);
  end loop;
end $$;
revoke create on schema public from public,anon,authenticated;
-- Arbitrary SQL and provider payment-confirmation APIs are server-only, even
-- when a caller has a valid cashier/owner JWT.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in
      ('query','exec_sql','execute_sql','_exec_sql','process_midtrans_topup_webhook',
       'process_doku_topup_webhook','setup_superadmin','sa_set_ai_limit')
  loop
    execute format('revoke execute on function %s from public,anon,authenticated',f.signature);
    execute format('grant execute on function %s to service_role',f.signature);
  end loop;
end $$;

notify pgrst,'reload schema';
