-- Run after offline-food-sync.sql INSIDE an outer transaction, then ROLLBACK.
do $$
declare
  u public.users%rowtype;
  b uuid := gen_random_uuid();
  d date := (now() at time zone 'Asia/Jakarta')::date-1;
  p jsonb;
  r jsonb;
  n integer;
  a numeric;
  denied boolean;
begin
  select * into u from public.users where auth_id is not null and owner_id is not null
    and is_active is true and is_approved is true limit 1;
  if u.id is null then raise exception 'Test requires an active fixture user'; end if;
  insert into public.branches(id,owner_id,name,is_active) values(b,u.owner_id,'ROLLBACK offline sync fixture',true);
  update public.users set branch_id=b,role='kasir' where id=u.id;
  perform set_config('request.jwt.claim.sub',u.auth_id::text,true);
  insert into public.menu_stock_components(branch_id,menu_name_key,component_key,qty_per_order)
    values(b,'test menu','ingredient a',2),(b,'test menu','ingredient b',1);
  insert into public.menu_stock(branch_id,menu_name,menu_name_key,stock_date,stock_awal,stock_terjual)
    values(b,'Ingredient A','ingredient a',d,10,0),(b,'Ingredient B','ingredient b',d,10,0),
          (b,'Ingredient A','ingredient a',d+1,100,0);
  p := jsonb_build_object('version',1,'account_id',u.auth_id,'branch_id',b,
    'order_number','TEST-OFFLINE-'||b,'created_at',(d::timestamp at time zone 'Asia/Jakarta'),
    'subtotal',20000,'discount',0,'tax',0,'service_charge_amount',0,'total',20000,
    'payment_method','cash','paid_amount',20000,'change_amount',0,
    'items',jsonb_build_array(jsonb_build_object('item_name','test menu','quantity',2,'price',10000,'subtotal',20000)));
  execute 'set local role authenticated';
  r := public.sync_paid_food_order(p);
  execute 'reset role';
  if r->>'stock_applied' <> 'true' then raise exception 'First sync failed: %',r; end if;
  r := public.sync_paid_food_order(p);
  select count(*) into n from public.orders where order_number=p->>'order_number';
  if n <> 1 then raise exception 'Duplicate receipt created'; end if;
  select stock_terjual into a from public.menu_stock where branch_id=b and menu_name_key='ingredient a' and stock_date=d;
  if a <> 4 then raise exception 'Retry deducted twice: %',a; end if;
  select stock_terjual into a from public.menu_stock where branch_id=b and stock_date=d+1;
  if a <> 0 then raise exception 'Historical receipt changed today stock'; end if;
  denied := false;
  begin
    perform public.sync_paid_food_order(p || '{"total":30000}'::jsonb);
  exception when sqlstate '22023' then denied := true;
  end;
  if not denied then raise exception 'Changed payload accepted'; end if;
  denied := false;
  begin
    perform public.sync_paid_food_order(p || jsonb_build_object('branch_id',gen_random_uuid()));
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'Foreign branch accepted'; end if;
  denied := false;
  begin
    perform public.sync_paid_food_order(p || jsonb_build_object('account_id',gen_random_uuid()));
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'Foreign account accepted'; end if;
  -- Force failure after ingredient A would be updated. All stock must roll back.
  update public.menu_stock set stock_awal=stock_terjual where branch_id=b and menu_name_key='ingredient b' and stock_date=d;
  p := p || jsonb_build_object('order_number','TEST-CONFLICT-'||b);
  r := public.sync_paid_food_order(p);
  if r->>'success' <> 'true' or r->>'stock_applied' <> 'false' then raise exception 'Stock conflict not preserved: %',r; end if;
  select count(*) into n from public.orders where order_number=p->>'order_number';
  if n <> 1 then raise exception 'Offline paid receipt disappeared'; end if;
  select stock_terjual into a from public.menu_stock where branch_id=b and menu_name_key='ingredient a' and stock_date=d;
  if a <> 4 then raise exception 'Partial ingredient deduction leaked'; end if;
  update public.menu_stock set stock_awal=20 where branch_id=b and menu_name_key='ingredient b' and stock_date=d;
  update public.menu_stock_components set qty_per_order=99 where branch_id=b and component_key='ingredient a';
  r := public.sync_paid_food_order(p);
  if r->>'stock_applied' <> 'true' then raise exception 'Stock repair retry failed: %',r; end if;
  select stock_terjual into a from public.menu_stock where branch_id=b and menu_name_key='ingredient a' and stock_date=d;
  if a <> 8 then raise exception 'Retry did not use frozen recipe: %',a; end if;
  if has_function_privilege('anon','public.sync_paid_food_order(jsonb)','execute') then
    raise exception 'Anonymous caller can execute endpoint';
  end if;
  -- Legacy order exists but has no receipt ledger: never assume a deduction.
  insert into public.orders(branch_id,order_number,order_type,status,total)
    values(b,'TEST-LEGACY-'||b,'food','paid',20000);
  r := public.sync_paid_food_order(p || jsonb_build_object('order_number','TEST-LEGACY-'||b));
  if r->>'stock_applied' <> 'false' then raise exception 'Ambiguous legacy receipt acknowledged'; end if;
end;
$$;
