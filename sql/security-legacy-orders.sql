-- Stable-key authenticated compatibility adapter for the existing retail/legacy API.
-- The old implementation is retained privately; all existing business logic runs
-- inside this same transaction, after identity and duplicate checks.
create table if not exists zela_sync.legacy_receipts(
 branch_id uuid not null, order_number text not null, account_id uuid not null,
 payload jsonb not null, result jsonb not null, created_at timestamptz not null default now(),
 primary key(branch_id,order_number)
);
alter table zela_sync.legacy_receipts enable row level security;
revoke all on zela_sync.legacy_receipts from public,anon,authenticated;
CREATE OR REPLACE FUNCTION zela_sync.legacy_insert_order_v1(p_cashier_email text DEFAULT NULL::text, p_cashier_id text DEFAULT NULL::text, p_cashier_name text DEFAULT NULL::text, p_branch_id uuid DEFAULT NULL::uuid, p_order_number text DEFAULT NULL::text, p_order_type text DEFAULT 'food'::text, p_status text DEFAULT 'completed'::text, p_subtotal numeric DEFAULT 0, p_discount numeric DEFAULT 0, p_tax numeric DEFAULT 0, p_total numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_paid_amount numeric DEFAULT 0, p_change_amount numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_items json DEFAULT NULL::json, p_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_owner_id uuid;
  v_cashier_uuid uuid := null;
  v_branch_id uuid;
  v_order_id bigint;
  v_order_number text;
  v_daily_seq integer;
  v_wib_date date;
begin
  if p_subtotal < 0 or p_total < 0 or p_discount < 0 or p_tax < 0 then
    return jsonb_build_object('success', false, 'error', 'invalid: negative values not allowed');
  end if;
  if p_total > 100000000 then
    return jsonb_build_object('success', false, 'error', 'invalid: total too large');
  end if;
  if p_payment_method not in (
    'cash','qris','transfer','kartu','card','debit','credit','other',
    'Tunai','QRIS','Transfer','Kartu',
    'online_gojek','online_grab','online_shopee',
    'online_internal','online_rusak'
  ) then
    return jsonb_build_object('success', false, 'error', 'invalid payment method: ' || p_payment_method);
  end if;

  if p_cashier_email is not null and p_cashier_email <> '' then
    select id, owner_id, branch_id
      into v_cashier_uuid, v_owner_id, v_branch_id
    from public.users
    where email = p_cashier_email
    limit 1;

    if v_owner_id is null then
      select id into v_owner_id
      from public.owners
      where email = p_cashier_email
      limit 1;
    end if;
  end if;

  if v_owner_id is null and p_cashier_id is not null and p_cashier_id <> '' then
    if p_cashier_id ~ '^[0-9a-f-]{36}$' then
      begin
        select id, owner_id, branch_id
          into v_cashier_uuid, v_owner_id, v_branch_id
        from public.users
        where id = p_cashier_id::uuid
        limit 1;
      exception when others then
        null;
      end;
    end if;
  end if;

  if v_owner_id is null and p_branch_id is not null then
    select owner_id into v_owner_id
    from public.branches
    where id = p_branch_id
    limit 1;
  end if;

  if v_owner_id is null then
    return jsonb_build_object('success', false, 'error', 'cashier not found: ' || coalesce(p_cashier_email, ''));
  end if;

  v_branch_id := coalesce(p_branch_id, v_branch_id);

  if p_items is not null and json_array_length(p_items) > 0 then
    -- Fails before orders/order_items and subscription balance are changed.
    perform public.assert_stock_available(v_branch_id, p_items);
  end if;

  v_wib_date := (coalesce(p_created_at, now()) at time zone 'Asia/Jakarta')::date;

  select coalesce(max(daily_seq), 0) + 1
    into v_daily_seq
  from public.orders
  where branch_id = v_branch_id
    and (created_at at time zone 'Asia/Jakarta')::date = v_wib_date;

  v_order_number := coalesce(
    nullif(p_order_number, ''),
    'ORD-' || to_char(v_wib_date, 'YYYYMMDD') || '-' || lpad(v_daily_seq::text, 4, '0')
  );

  if exists (select 1 from public.orders where order_number = v_order_number) then
    v_order_number := v_order_number || '-' || substr(gen_random_uuid()::text, 1, 4);
  end if;

  insert into public.orders (
    order_number, cashier_id, cashier_name, branch_id,
    order_type, status, subtotal, discount, tax, total,
    payment_method, paid_amount, change_amount, notes, created_at, daily_seq
  ) values (
    v_order_number, v_cashier_uuid, p_cashier_name, v_branch_id,
    p_order_type, p_status, p_subtotal, p_discount, p_tax, p_total,
    p_payment_method, p_paid_amount, p_change_amount, p_notes,
    coalesce(p_created_at, now()), v_daily_seq
  ) returning id into v_order_id;

  if p_items is not null and json_array_length(p_items) > 0 then
    insert into public.order_items (order_id, item_name, quantity, unit, price, subtotal)
    select
      v_order_id,
      coalesce(nullif(item->>'item_name', ''), nullif(item->>'name', '')),
      greatest(coalesce((item->>'quantity')::numeric, 0), 0),
      nullif(trim(coalesce(item->>'unit', '')), ''),
      greatest(coalesce((item->>'price')::numeric, 0), 0),
      greatest(coalesce((item->>'subtotal')::numeric, 0), 0)
    from json_array_elements(p_items) as item
    where coalesce(nullif(item->>'item_name', ''), nullif(item->>'name', '')) is not null;
  end if;

  perform public.deduct_transaction(v_owner_id::uuid);

  return jsonb_build_object(
    'success', true,
    'order_id', v_order_id,
    'order_number', v_order_number,
    'daily_seq', v_daily_seq
  );
end;
$function$
;
revoke all on function zela_sync.legacy_insert_order_v1(text,text,text,uuid,text,text,text,numeric,numeric,numeric,numeric,text,numeric,numeric,text,json,timestamptz) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION zela_sync.secure_legacy_order(p_cashier_email text DEFAULT NULL::text, p_cashier_id text DEFAULT NULL::text, p_cashier_name text DEFAULT NULL::text, p_branch_id uuid DEFAULT NULL::uuid, p_order_number text DEFAULT NULL::text, p_order_type text DEFAULT 'food'::text, p_status text DEFAULT 'completed'::text, p_subtotal numeric DEFAULT 0, p_discount numeric DEFAULT 0, p_tax numeric DEFAULT 0, p_total numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_paid_amount numeric DEFAULT 0, p_change_amount numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_items json DEFAULT NULL::json, p_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 a jsonb := zela_sync.actor();
 v_branch uuid := p_branch_id;
 v_account uuid := auth.uid();
 v_payload jsonb;
 v_previous zela_sync.legacy_receipts%rowtype;
 v_result jsonb;
 v_item jsonb;
begin
 if auth.role()='service_role' then
   v_account:=coalesce(v_account,'00000000-0000-0000-0000-000000000000'::uuid);
 else
   if a is null then raise exception 'Login online diperlukan' using errcode='42501'; end if;
   v_branch:=coalesce(v_branch,(a->>'branch')::uuid);
   if not zela_sync.can_access_branch(v_branch) then
     raise exception 'Tidak berhak mengirim transaksi cabang ini' using errcode='42501';
   end if;
 end if;
 if v_branch is null or p_order_number is null or length(btrim(p_order_number)) not between 1 and 160 then
   raise exception 'Cabang dan nomor receipt stabil diperlukan' using errcode='22023';
 end if;
 if p_items is null or json_typeof(p_items)<>'array' then
   raise exception 'Daftar item tidak valid' using errcode='22023'; end if;
 if json_array_length(p_items) not between 1 and 500 then
   raise exception 'Jumlah item tidak valid' using errcode='22023'; end if;
 if p_subtotal is null or p_total is null or p_discount is null or p_tax is null or
    p_paid_amount is null or p_change_amount is null or
    not (p_subtotal between 0 and 100000000 and p_total between 0 and 100000000
     and p_discount between 0 and 100000000 and p_tax between 0 and 100000000
     and p_paid_amount between 0 and 100000000 and p_change_amount between 0 and 100000000) then
   raise exception 'Nominal tidak valid' using errcode='22023'; end if;
 if p_created_at>now()+interval '10 minutes' then
   raise exception 'Tanggal transaksi tidak valid' using errcode='22023'; end if;
 for v_item in select value::jsonb from json_array_elements(p_items) loop
   if coalesce(length(btrim(coalesce(v_item->>'item_name',v_item->>'name'))),0) not between 1 and 200
     or (v_item->>'quantity') is null or not ((v_item->>'quantity')::numeric between 0.000001 and 1000000)
     or (v_item->>'price') is null or not ((v_item->>'price')::numeric between 0 and 100000000)
     or (v_item->>'subtotal') is null or not ((v_item->>'subtotal')::numeric between 0 and 100000000) then
     raise exception 'Item transaksi tidak valid' using errcode='22023';
   end if;
 end loop;
 v_payload:=jsonb_build_object('branch',v_branch,'number',p_order_number,'type',p_order_type,
  'status',p_status,'subtotal',p_subtotal,'discount',p_discount,'tax',p_tax,'total',p_total,
  'payment',p_payment_method,'paid',p_paid_amount,'change',p_change_amount,
  'notes',p_notes,'items',p_items::jsonb,'created',p_created_at);
 -- Same lock family as the food outbox API protects branch daily sequence.
 perform pg_advisory_xact_lock(hashtextextended('zela-food-sync:'||v_branch::text,0));
 select * into v_previous from zela_sync.legacy_receipts
   where branch_id=v_branch and order_number=p_order_number for update;
 if found then
   if v_previous.account_id<>v_account or v_previous.payload<>v_payload then
     raise exception 'Nomor receipt sudah dipakai dengan identitas/isi berbeda' using errcode='22023';
   end if;
   return v_previous.result;
 end if;
 if exists(select 1 from public.orders where order_number=p_order_number) then
   raise exception 'Receipt lama sudah ada; perlu rekonsiliasi, jangan kirim sebagai transaksi baru' using errcode='23505';
 end if;
 v_result:=zela_sync.legacy_insert_order_v1(
   coalesce(a->>'email',p_cashier_email),coalesce(a->>'id',p_cashier_id),
   coalesce(a->>'name',p_cashier_name),v_branch,p_order_number,p_order_type,p_status,
   p_subtotal,p_discount,p_tax,p_total,p_payment_method,p_paid_amount,p_change_amount,
   p_notes,p_items,p_created_at);
 if v_result->>'success'='true' then
   insert into zela_sync.legacy_receipts(branch_id,order_number,account_id,payload,result)
     values(v_branch,p_order_number,v_account,v_payload,v_result);
 end if;
 return v_result;
end;
$function$;
revoke all on function zela_sync.secure_legacy_order(text,text,text,uuid,text,text,text,numeric,numeric,numeric,numeric,text,numeric,numeric,text,json,timestamptz) from public,anon;
grant execute on function zela_sync.secure_legacy_order(text,text,text,uuid,text,text,text,numeric,numeric,numeric,numeric,text,numeric,numeric,text,json,timestamptz) to authenticated,service_role;
CREATE OR REPLACE FUNCTION public.insert_order(p_cashier_email text DEFAULT NULL::text, p_cashier_id text DEFAULT NULL::text, p_cashier_name text DEFAULT NULL::text, p_branch_id uuid DEFAULT NULL::uuid, p_order_number text DEFAULT NULL::text, p_order_type text DEFAULT 'food'::text, p_status text DEFAULT 'completed'::text, p_subtotal numeric DEFAULT 0, p_discount numeric DEFAULT 0, p_tax numeric DEFAULT 0, p_total numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_paid_amount numeric DEFAULT 0, p_change_amount numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_items json DEFAULT NULL::json, p_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
begin
 return zela_sync.secure_legacy_order(p_cashier_email,p_cashier_id,p_cashier_name,p_branch_id,p_order_number,p_order_type,p_status,p_subtotal,p_discount,p_tax,p_total,p_payment_method,p_paid_amount,p_change_amount,p_notes,p_items,p_created_at);
end;
$function$;

revoke all on function public.insert_order(text,text,text,uuid,text,text,text,numeric,numeric,numeric,numeric,text,numeric,numeric,text,json,timestamptz) from public,anon;
grant execute on function public.insert_order(text,text,text,uuid,text,text,text,numeric,numeric,numeric,numeric,text,numeric,numeric,text,json,timestamptz) to authenticated,service_role;
notify pgrst,'reload schema';
