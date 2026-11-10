-- Additive authenticated catalog API; preserves existing table/cart IDs.
create or replace function zela_sync.restaurant_table_catalog(
  p_branch_id uuid, p_action text, p_id bigint, p_name text,
  p_zone text, p_capacity integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user public.users%rowtype;
  v_owner uuid;
  v_row public.restaurant_tables%rowtype;
  v_name text := btrim(p_name);
  v_zone text := btrim(p_zone);
begin
  if auth.uid() is null then
    raise exception 'Login online terlebih dahulu' using errcode='42501';
  end if;
  select * into v_user from public.users where auth_id=auth.uid()
    and is_active is true and is_approved is true;
  if not found then raise exception 'Akun tidak aktif/disetujui' using errcode='42501'; end if;
  if coalesce(v_user.role,'') not in ('kasir','owner','admin','manajer','superadmin') then
    raise exception 'Role tidak berhak mengelola meja' using errcode='42501';
  end if;
  select owner_id into v_owner from public.branches
    where id=p_branch_id and is_active is true;
  if v_owner is null or (v_user.role <> 'superadmin' and (
      v_user.owner_id is distinct from v_owner or
      (v_user.branch_id is distinct from p_branch_id and
       v_user.role not in ('owner','admin','manajer')))) then
    raise exception 'Tidak berhak mengelola meja cabang ini' using errcode='42501';
  end if;
  if p_action='list' then
    return coalesce((select jsonb_agg(to_jsonb(t) order by t.zone,t.name)
      from public.restaurant_tables t where t.branch_id=p_branch_id), '[]'::jsonb);
  end if;
  if p_action='archive' then
    if v_user.role not in ('owner','admin','manajer','superadmin') then
      raise exception 'Hanya pengelola yang dapat menghapus meja' using errcode='42501';
    end if;
    select * into v_row from public.restaurant_tables
      where id=p_id and branch_id=p_branch_id and is_active is true for update;
    if not found then raise exception 'Meja tidak ditemukan' using errcode='22023'; end if;
    if v_row.status <> 'empty' or exists(select 1 from public.table_carts
        where branch_id=p_branch_id and table_id=p_id) then
      raise exception 'Selesaikan pesanan meja terlebih dahulu' using errcode='22023';
    end if;
    update public.restaurant_tables set is_active=false where id=p_id returning * into v_row;
    return to_jsonb(v_row);
  end if;
  if p_action is distinct from 'save' then
    raise exception 'Aksi meja tidak valid' using errcode='22023';
  end if;
  if v_name is null or length(v_name) not between 1 and 80 or
     v_zone is null or length(v_zone) not between 1 and 40 or
     p_capacity is null or p_capacity not between 1 and 100 then
    raise exception 'Nama, area, atau kapasitas meja tidak valid' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('zela-table:'||p_branch_id::text,0));
  if p_id is not null then
    select * into v_row from public.restaurant_tables where id=p_id
      and branch_id=p_branch_id and is_active is true for update;
    if not found then raise exception 'Meja tidak ditemukan di cabang ini' using errcode='22023'; end if;
  end if;
  if exists(select 1 from public.restaurant_tables where branch_id=p_branch_id
      and lower(btrim(name))=lower(v_name) and (p_id is null or id<>p_id)) then
    -- An unchanged create retry after a lost HTTP response is safe to return.
    if p_id is null then
      select * into v_row from public.restaurant_tables where branch_id=p_branch_id
        and lower(btrim(name))=lower(v_name) and zone=v_zone
        and capacity=p_capacity and is_active is true;
      if found then return to_jsonb(v_row); end if;
    end if;
    raise exception 'Nama meja sudah digunakan di cabang ini' using errcode='23505';
  end if;
  if p_id is null then
    insert into public.restaurant_tables(branch_id,name,zone,capacity)
      values(p_branch_id,v_name,v_zone,p_capacity) returning * into v_row;
  else
    update public.restaurant_tables set name=v_name,zone=v_zone,capacity=p_capacity
      where id=p_id and branch_id=p_branch_id returning * into v_row;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke all on function zela_sync.restaurant_table_catalog(uuid,text,bigint,text,text,integer) from public,anon;
grant usage on schema zela_sync to authenticated;
grant execute on function zela_sync.restaurant_table_catalog(uuid,text,bigint,text,text,integer) to authenticated;

create or replace function public.app_restaurant_tables(
  p_branch_id uuid, p_action text default 'list', p_id bigint default null,
  p_name text default null, p_zone text default 'Dalam', p_capacity integer default 4
) returns jsonb language sql security invoker set search_path = '' as $$
  select zela_sync.restaurant_table_catalog(p_branch_id,p_action,p_id,p_name,p_zone,p_capacity);
$$;
revoke all on function public.app_restaurant_tables(uuid,text,bigint,text,text,integer) from public,anon;
grant execute on function public.app_restaurant_tables(uuid,text,bigint,text,text,integer) to authenticated;
notify pgrst, 'reload schema';
