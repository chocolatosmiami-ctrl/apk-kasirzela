-- Execute as one batch. All fixture rows and mutations are rolled back.
begin;
do $$
declare
  u public.users%rowtype;
  b uuid;
  foreign_id bigint;
  r jsonb;
  again jsonb;
  v_id bigint;
  test_name text := 'ROLLBACK-CATALOG-'||gen_random_uuid()::text;
  denied boolean;
begin
  select usr.* into u from public.users usr join public.branches br
    on br.id=usr.branch_id and br.owner_id=usr.owner_id and br.is_active is true
    where usr.role='kasir' and usr.auth_id is not null
      and usr.is_active is true and usr.is_approved is true limit 1;
  if u.id is null then raise exception 'An active authenticated cashier is required'; end if;
  select branch_id,id into b,foreign_id from public.restaurant_tables where branch_id<>u.branch_id limit 1;
  perform set_config('request.jwt.claim.sub',u.auth_id::text,true);
  execute 'set local role authenticated';
  r := public.app_restaurant_tables(u.branch_id,'save',null,test_name,'Teras',6);
  v_id := (r->>'id')::bigint;
  again := public.app_restaurant_tables(u.branch_id,'save',null,test_name,'Teras',6);
  if (again->>'id')::bigint <> v_id then raise exception 'Create retry duplicated a table'; end if;
  execute 'reset role';
  update public.restaurant_tables set status='occupied',customer_name='Synthetic guest' where id=v_id;
  execute 'set local role authenticated';
  r := public.app_restaurant_tables(u.branch_id,'save',v_id,test_name||'-renamed','VIP',8);
  if r->>'name' <> test_name||'-renamed' or r->>'zone'<>'VIP'
     or (r->>'capacity')::integer<>8 or r->>'status'<>'occupied'
     or r->>'customer_name'<>'Synthetic guest' then
    raise exception 'Rename changed status/customer or failed to persist metadata';
  end if;
  again := public.app_restaurant_tables(u.branch_id);
  if not exists(select 1 from jsonb_array_elements(again) x where (x->>'id')::bigint=v_id
      and x->>'name'=test_name||'-renamed') then raise exception 'Reload lost the edited table'; end if;
  denied := false;
  begin
    perform public.app_restaurant_tables(u.branch_id,'save',null,test_name||'-renamed','VIP',9);
  exception when unique_violation then denied := true; end;
  if not denied then raise exception 'Duplicate name accepted'; end if;
  denied := false;
  begin
    perform public.app_restaurant_tables(u.branch_id,'save',null,'','Dalam',0);
  exception when sqlstate '22023' then denied := true; end;
  if not denied then raise exception 'Invalid form accepted'; end if;
  denied := false;
  begin perform public.app_restaurant_tables(b);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Foreign branch readable'; end if;
  denied := false;
  begin perform public.app_restaurant_tables(u.branch_id,'save',foreign_id,test_name,'Dalam',4);
  exception when sqlstate '22023' then denied := true; end;
  if not denied then raise exception 'Foreign table editable'; end if;
  denied := false;
  begin perform public.app_restaurant_tables(u.branch_id,'archive',v_id);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Cashier may archive a table'; end if;
  execute 'reset role';
  if has_function_privilege('anon',
      'public.app_restaurant_tables(uuid,text,bigint,text,text,integer)','execute') then
    raise exception 'Anonymous user can call API';
  end if;
end;
$$;
do $$
declare
  u public.users%rowtype;
  r jsonb;
begin
  select usr.* into u from public.users usr join public.branches br
    on br.id=usr.branch_id and br.owner_id=usr.owner_id and br.is_active is true
    where usr.role='manajer' and usr.auth_id is not null
      and usr.is_active is true and usr.is_approved is true limit 1;
  if u.id is null then raise exception 'An active manager fixture is required'; end if;
  perform set_config('request.jwt.claim.sub',u.auth_id::text,true);
  execute 'set local role authenticated';
  r := public.app_restaurant_tables(u.branch_id,'save',null,
    'ROLLBACK-CATALOG-MGR-'||gen_random_uuid()::text,'Dalam',4);
  r := public.app_restaurant_tables(u.branch_id,'archive',(r->>'id')::bigint);
  if r->>'is_active' <> 'false' then raise exception 'Manager archive did not persist'; end if;
  execute 'reset role';
end;
$$;
select 'PASS: authenticated cashier create/retry/rename/reload, preserve status/customer, duplicate/invalid form, foreign branch/table denial, anonymous denied' as checks;
rollback;
