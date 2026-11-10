-- Additive patch for the inspected DB Kasir Sg schema. Deploy before the APK.
-- Old insert_order/deduct_menu_stock remain unchanged for old APKs.
begin;
create schema if not exists zela_sync;
revoke all on schema zela_sync from public, anon;
grant usage on schema zela_sync to authenticated;

create table if not exists zela_sync.food_receipts (
  branch_id uuid not null references public.branches(id),
  order_number text not null,
  account_id uuid not null,
  order_id bigint not null unique references public.orders(id),
  payload jsonb not null,
  stock_date date not null,
  requirements jsonb not null,
  stock_applied boolean not null default false,
  last_error text,
  created_at timestamptz not null default now(),
  primary key (branch_id, order_number)
);
alter table zela_sync.food_receipts enable row level security;
revoke all on zela_sync.food_receipts from public, anon, authenticated;

create or replace function zela_sync.accept_food_receipt(p_payload jsonb)
-- Existing order-item/subscription triggers use unqualified public relations.
-- pg_catalog first and pg_temp last prevent temporary relation shadowing.
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_branch uuid := (p_payload->>'branch_id')::uuid;
  v_number text := p_payload->>'order_number';
  v_time timestamptz := (p_payload->>'created_at')::timestamptz;
  v_date date;
  v_user public.users%rowtype;
  v_owner uuid;
  v_receipt zela_sync.food_receipts%rowtype;
  v_order_id bigint;
  v_daily integer;
  v_requirements jsonb;
  v_item jsonb;
  v_need record;
  v_stock public.menu_stock%rowtype;
  v_last public.menu_stock%rowtype;
  v_enforced boolean;
begin
  -- Validate real JWT identity before returning even an existing receipt.
  if v_uid is null or p_payload->>'account_id' is distinct from v_uid::text then
    raise exception 'Login kembali dengan akun pembuat transaksi' using errcode = '42501';
  end if;
  select * into v_user from public.users
    where auth_id = v_uid and is_active is true and is_approved is true;
  if not found then
    raise exception 'Akun kasir tidak aktif/disetujui' using errcode = '42501';
  end if;
  select owner_id into v_owner from public.branches where id = v_branch and is_active is true;
  if v_owner is null or v_owner is distinct from v_user.owner_id
     or (v_user.branch_id is distinct from v_branch and v_user.role not in ('owner','manajer')) then
    raise exception 'Akun tidak berhak mengirim transaksi cabang ini' using errcode = '42501';
  end if;
  if v_number is null or length(v_number) not between 1 and 160 or v_time is null
     or v_time > now() + interval '10 minutes' or p_payload->>'version' is distinct from '1'
     or jsonb_typeof(p_payload->'items') is distinct from 'array' then
    raise exception 'Payload transaksi tidak valid' using errcode = '22023';
  end if;
  if jsonb_array_length(p_payload->'items') not between 1 and 500 then
    raise exception 'Daftar item kosong/terlalu panjang' using errcode = '22023';
  end if;
  if (p_payload->>'payment_method') is null or (p_payload->>'payment_method') not in
     ('cash','qris','transfer','kartu','card','debit','credit','other',
      'online_gojek','online_grab','online_shopee','online_internal','online_rusak') then
    raise exception 'Metode pembayaran tidak valid' using errcode = '22023';
  end if;
  foreach v_number in array array['subtotal','discount','tax','service_charge_amount','total','paid_amount','change_amount'] loop
    if p_payload->>v_number is null or (p_payload->>v_number)::numeric not between 0 and 100000000 then
      raise exception 'Nominal % tidak valid', v_number using errcode = '22023';
    end if;
  end loop;
  v_number := p_payload->>'order_number';
  for v_item in select value from jsonb_array_elements(p_payload->'items') loop
    if coalesce(length(btrim(v_item->>'item_name')),0) not between 1 and 200
       or v_item->>'quantity' is null or (v_item->>'quantity')::numeric not between 0.000001 and 1000000
       or v_item->>'price' is null or (v_item->>'price')::numeric not between 0 and 100000000
       or v_item->>'subtotal' is null or (v_item->>'subtotal')::numeric not between 0 and 100000000 then
      raise exception 'Item transaksi tidak valid' using errcode = '22023';
    end if;
  end loop;
  v_date := (v_time at time zone 'Asia/Jakarta')::date;
  -- Stable branch lock serializes retries and sequence allocation for this API.
  perform pg_advisory_xact_lock(hashtextextended('zela-food-sync:' || v_branch::text, 0));
  select * into v_receipt from zela_sync.food_receipts
    where branch_id = v_branch and order_number = v_number for update;
  if found then
    if v_receipt.account_id <> v_uid or v_receipt.payload <> p_payload then
      raise exception 'Nomor transaksi sama dengan isi berbeda' using errcode = '22023';
    end if;
    if v_receipt.stock_applied then
      return jsonb_build_object('success',true,'stock_applied',true,'order_id',v_receipt.order_id);
    end if;
    v_order_id := v_receipt.order_id;
    v_requirements := v_receipt.requirements;
  else
    -- Legacy records may already have had stock deducted. Never guess or repeat it.
    if exists (select 1 from public.orders where order_number = v_number) then
      return jsonb_build_object('success',true,'stock_applied',false,
        'error','Order lama sudah ada di server; admin perlu rekonsiliasi stok, jangan potong ulang otomatis');
    end if;
    select exists(select 1 from public.menu_stock_components where branch_id=v_branch)
       or exists(select 1 from public.menu_stock where branch_id=v_branch and stock_date=v_date)
       into v_enforced;
    -- Freeze recipe requirements when first accepted, so a retry cannot use a new recipe.
    with items as (
      select lower(btrim(i->>'item_name')) as name, sum((i->>'quantity')::numeric) as qty
      from jsonb_array_elements(p_payload->'items') i group by 1
    ), requirements as (
      select c.component_key as name, i.qty*c.qty_per_order as qty
      from items i join public.menu_stock_components c
        on c.branch_id=v_branch and c.menu_name_key=i.name
      union all
      select i.name, i.qty from items i where v_enforced and (
        exists(select 1 from public.menu_stock s where s.branch_id=v_branch
          and s.menu_name_key=i.name and s.stock_date=v_date)
        or not exists(select 1 from public.menu_stock_components c
          where c.branch_id=v_branch and c.menu_name_key=i.name)
      ) and not exists(select 1 from public.menu_stock_components c
        where c.branch_id=v_branch and c.menu_name_key=i.name and c.component_key=i.name)
    ), totals as (select name,sum(qty) as qty from requirements group by name)
    select coalesce(jsonb_agg(jsonb_build_object('name',name,'qty',qty) order by name),'[]'::jsonb)
      into v_requirements from totals;
    select coalesce(max(daily_seq),0)+1 into v_daily from public.orders
      where branch_id=v_branch and (created_at at time zone 'Asia/Jakarta')::date=v_date;
    insert into public.orders(order_number,cashier_id,cashier_name,branch_id,order_type,status,
      subtotal,discount,tax,service_charge_amount,total,payment_method,paid_amount,change_amount,
      notes,created_at,daily_seq)
    values(v_number,v_user.id,v_user.name,v_branch,'food','paid',
      (p_payload->>'subtotal')::numeric,(p_payload->>'discount')::numeric,
      (p_payload->>'tax')::numeric,(p_payload->>'service_charge_amount')::numeric,
      (p_payload->>'total')::numeric,p_payload->>'payment_method',
      (p_payload->>'paid_amount')::numeric,(p_payload->>'change_amount')::numeric,
      p_payload->>'notes',v_time,v_daily) returning id into v_order_id;
    insert into public.order_items(order_id,item_name,quantity,unit,price,subtotal)
      select v_order_id,i->>'item_name',(i->>'quantity')::numeric,nullif(i->>'unit',''),
        (i->>'price')::numeric,(i->>'subtotal')::numeric
      from jsonb_array_elements(p_payload->'items') i;
    insert into zela_sync.food_receipts(branch_id,order_number,account_id,order_id,payload,stock_date,requirements)
      values(v_branch,v_number,v_uid,v_order_id,p_payload,v_date,v_requirements);
    -- Preserve the existing per-receipt subscription hook, once only.
    perform public.deduct_transaction(v_owner);
  end if;
  -- A stock conflict must not erase a receipt which was already paid offline.
  -- This subtransaction rolls back ALL ingredient updates on any stock error.
  begin
    for v_need in select r->>'name' as name,(r->>'qty')::numeric as qty
      from jsonb_array_elements(v_requirements) r order by r->>'name' loop
      if v_need.qty <= 0 then raise exception 'Jumlah resep tidak valid'; end if;
      select * into v_stock from public.menu_stock
        where branch_id=v_branch and menu_name_key=v_need.name and stock_date=v_date for update;
      if not found and exists(select 1 from public.stock_skip_items
          where branch_id=v_branch and lower(btrim(bahan_name))=v_need.name) then
        select * into v_last from public.menu_stock
          where branch_id=v_branch and menu_name_key=v_need.name and stock_date<v_date
          order by stock_date desc limit 1 for update;
        if found then
          insert into public.menu_stock(branch_id,menu_item_id,menu_name,menu_name_key,stock_date,
            stock_awal,stock_terjual,min_alert,created_by)
          values(v_branch,0,v_last.menu_name,v_need.name,v_date,
            greatest(v_last.stock_sisa,0),0,v_last.min_alert,'offline-sync-carry');
          select * into v_stock from public.menu_stock
            where branch_id=v_branch and menu_name_key=v_need.name and stock_date=v_date for update;
        end if;
      end if;
      if v_stock.id is null then
        raise exception 'Stok % tanggal % belum diatur',v_need.name,v_date;
      end if;
      -- A later carry-over already depends on this non-reset balance. Do not
      -- silently rewrite history while leaving the carried current stock wrong.
      if v_date < (now() at time zone 'Asia/Jakarta')::date
         and exists(select 1 from public.stock_skip_items where branch_id=v_branch
           and lower(btrim(bahan_name))=v_need.name)
         and exists(select 1 from public.menu_stock where branch_id=v_branch
           and menu_name_key=v_need.name and stock_date>v_date) then
        raise exception 'Stok tidak-reset % lintas hari perlu rekonsiliasi admin',v_need.name;
      end if;
      if v_stock.stock_sisa < v_need.qty then
        raise exception 'Stok % tanggal % kurang: sisa %, perlu %',v_need.name,v_date,v_stock.stock_sisa,v_need.qty;
      end if;
      update public.menu_stock set stock_terjual=stock_terjual+v_need.qty,updated_at=now()
        where id=v_stock.id;
    end loop;
    update zela_sync.food_receipts set stock_applied=true,last_error=null
      where branch_id=v_branch and order_number=v_number;
  exception when others then
    update zela_sync.food_receipts set last_error=sqlerrm
      where branch_id=v_branch and order_number=v_number;
    return jsonb_build_object('success',true,'stock_applied',false,'order_id',v_order_id,'error',sqlerrm);
  end;
  return jsonb_build_object('success',true,'stock_applied',true,'order_id',v_order_id);
end;
$$;
revoke all on function zela_sync.accept_food_receipt(jsonb) from public, anon;
grant execute on function zela_sync.accept_food_receipt(jsonb) to authenticated;

create or replace function public.sync_paid_food_order(p_payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select zela_sync.accept_food_receipt(p_payload);
$$;
revoke all on function public.sync_paid_food_order(jsonb) from public, anon;
grant execute on function public.sync_paid_food_order(jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
