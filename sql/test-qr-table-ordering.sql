-- Synthetic fixtures ONLY. Run in an empty, isolated schema clone; never on production.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL session_replication_role=replica;
INSERT INTO auth.users(id,email,role,aud) VALUES
('00000000-0000-4000-8000-000000000001','qr-owner-a@example.invalid','authenticated','authenticated'),
('00000000-0000-4000-8000-000000000002','qr-owner-b@example.invalid','authenticated','authenticated'),
('00000000-0000-4000-8000-000000000011','qr-cash-a@example.invalid','authenticated','authenticated'),
('00000000-0000-4000-8000-000000000012','qr-cash-b@example.invalid','authenticated','authenticated');
INSERT INTO public.owners(id,auth_id,name,email,business_name) VALUES
('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','Fixture A','qr-owner-a@example.invalid','Fixture A'),
('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','Fixture B','qr-owner-b@example.invalid','Fixture B');
INSERT INTO public.branches(id,owner_id,name,mode) VALUES
('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Fixture A','food'),
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Fixture B','food');
INSERT INTO public.users(auth_id,owner_id,branch_id,name,email,role,is_active,is_approved) VALUES
('00000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Fixture cashier A','qr-cash-a@example.invalid','kasir',true,true),
('00000000-0000-4000-8000-000000000012','10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','Fixture cashier B','qr-cash-b@example.invalid','kasir',true,true);
INSERT INTO public.subscriptions(owner_id,balance,cost_per_trx,is_locked,is_trial) VALUES
('10000000-0000-4000-8000-000000000001',100000,300,false,false),('10000000-0000-4000-8000-000000000002',100000,300,false,false);
INSERT INTO public.restaurant_tables(id,branch_id,name,status) VALUES
(910001,'20000000-0000-4000-8000-000000000001','Fixture table A','empty'),
(920001,'20000000-0000-4000-8000-000000000002','Fixture table B','empty');
INSERT INTO public.menu_items(id,branch_id,name,price,is_available) VALUES
(910001,'20000000-0000-4000-8000-000000000001','Fixture dish',20000,true),
(920001,'20000000-0000-4000-8000-000000000002','Foreign dish',30000,true);
INSERT INTO public.menu_stock(branch_id,menu_name,menu_name_key,stock_date,stock_awal,stock_terjual)
VALUES('20000000-0000-4000-8000-000000000001','Fixture rice','fixture rice',(now() AT TIME ZONE 'Asia/Jakarta')::date,10,0);
INSERT INTO public.menu_stock_components(branch_id,menu_name_key,component_key,qty_per_order)
VALUES('20000000-0000-4000-8000-000000000001','fixture dish','fixture rice',2);
SET LOCAL session_replication_role=origin;
DO $test$
DECLARE a uuid:='00000000-0000-4000-8000-000000000011'; actor_b uuid:='00000000-0000-4000-8000-000000000012';
 branch uuid:='20000000-0000-4000-8000-000000000001'; branch_b uuid:='20000000-0000-4000-8000-000000000002';
 link text; visit uuid; token text:=repeat('a',64); token2 text:=repeat('b',64);
 r jsonb; again jsonb; batch uuid; batch2 uuid; pending_batch uuid; bill jsonb;
 items jsonb; payload jsonb; manual jsonb; old_balance numeric; before_stock numeric; denied boolean; job uuid;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 IF has_schema_privilege('authenticated','zela_qr','USAGE') OR has_schema_privilege('anon','zela_qr','USAGE')
 OR has_function_privilege('anon','public.qr_guest_v1(text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.qr_staff_v1(uuid,text,jsonb)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.qr_guest_v1(text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.get_menu_stock_today_before_qr_v1(uuid)','EXECUTE') THEN RAISE EXCEPTION 'QRTEST: ACL failure'; END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='zela_qr' AND c.relkind='r' AND c.relrowsecurity)<>5 THEN RAISE EXCEPTION 'QRTEST: private RLS missing'; END IF;
 r:=public.qr_staff_v1(a,'enable',jsonb_build_object('branch_id',branch,'table_id',910001));link:=r->>'token';
 r:=public.qr_guest_v1('menu',jsonb_build_object('link_token',link));
 IF r->>'state'<>'ready' OR jsonb_array_length(r->'menu')<>1 OR NOT (r->'menu'->0->>'available')::boolean OR EXISTS(SELECT 1 FROM zela_qr.visits) THEN RAISE EXCEPTION 'QRTEST: ready/catalog scoping or scan created visit'; END IF;
 denied:=false;BEGIN PERFORM public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token,'name',''));EXCEPTION WHEN SQLSTATE '22023' THEN denied:=true;END;
 IF NOT denied OR EXISTS(SELECT 1 FROM zela_qr.visits) THEN RAISE EXCEPTION 'QRTEST: invalid join created visit'; END IF;
 UPDATE public.restaurant_tables SET status='occupied' WHERE id=910001;
 denied:=false;BEGIN PERFORM public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token,'name','Fixture guest A'));EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=true;END;
 IF NOT denied OR EXISTS(SELECT 1 FROM zela_qr.visits) THEN RAISE EXCEPTION 'QRTEST: auto join overwrote occupied legacy table'; END IF;
 UPDATE public.restaurant_tables SET status='empty' WHERE id=910001;
 r:=public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token,'name','Fixture guest A'));visit:=(r->>'visit_id')::uuid;
 IF (SELECT count(*) FROM zela_qr.visits)<>1 OR (SELECT status FROM public.restaurant_tables WHERE id=910001)<>'occupied' THEN RAISE EXCEPTION 'QRTEST: auto visit creation'; END IF;
 r:=public.qr_staff_v1(a,'list',jsonb_build_object('branch_id',branch));
 IF jsonb_array_length(r->'tables')<>1 OR jsonb_array_length(r->'orders')<>0 THEN RAISE EXCEPTION 'QRTEST: staff list scoping'; END IF;
 r:=public.qr_guest_v1('menu',jsonb_build_object('link_token',link));
 IF r->'menu'->0->>'available'<>'true' THEN RAISE EXCEPTION 'QRTEST: open menu unavailable'; END IF;
 again:=public.qr_staff_v1(a,'open',jsonb_build_object('branch_id',branch,'table_id',910001));
 IF again->>'visit_id'<>visit::text THEN RAISE EXCEPTION 'QRTEST: duplicate visit'; END IF;
 r:=public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token,'name','Fixture guest A'));
 again:=public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token,'name','Changed name'));
 IF again->>'name'<>'Fixture guest A' THEN RAISE EXCEPTION 'QRTEST: join retry changed identity'; END IF;
 r:=public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token2,'name','Fixture guest B'));
 items:=jsonb_build_array(jsonb_build_object('menu_id',910001,'quantity',2,'price',20000,'note','Fixture note'));
 r:=public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token,'request_id','30000000-0000-4000-8000-000000000001','items',items));batch:=(r->>'id')::uuid;
 again:=public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token,'request_id','30000000-0000-4000-8000-000000000001','items',items));
 IF again->>'id'<>batch::text OR (SELECT count(*) FROM zela_qr.batches)<>1 THEN RAISE EXCEPTION 'QRTEST: duplicated request'; END IF;
 denied:=false;BEGIN PERFORM public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token,'request_id','30000000-0000-4000-8000-000000000001','items','[]'::jsonb));EXCEPTION WHEN SQLSTATE '22023' THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: changed retry accepted'; END IF;
 r:=public.qr_guest_v1('status',jsonb_build_object('link_token',link,'guest_token',token2));
 IF jsonb_array_length(r->'orders')<>0 THEN RAISE EXCEPTION 'QRTEST: customer privacy'; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 denied:=false;BEGIN PERFORM public.qr_staff_v1(actor_b,'accept',jsonb_build_object('branch_id',branch,'batch_id',batch));EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: cross-owner accept'; END IF;
 r:=public.qr_staff_v1(a,'accept',jsonb_build_object('branch_id',branch,'batch_id',batch));
 again:=public.qr_staff_v1(a,'accept',jsonb_build_object('branch_id',branch,'batch_id',batch));
 IF r->>'sequence'<>'1' OR again->>'accepted'<>'true' THEN RAISE EXCEPTION 'QRTEST: acceptance retry'; END IF;
 IF (SELECT stock_sisa FROM public.get_menu_stock_today(branch) WHERE menu_name_key='fixture rice')<>6 THEN RAISE EXCEPTION 'QRTEST: reservation not visible in POS'; END IF;
 denied:=false;BEGIN PERFORM public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token,'request_id','30000000-0000-4000-8000-000000000002','items',jsonb_build_array(jsonb_build_object('menu_id',920001,'quantity',1,'price',30000))));EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: foreign menu accepted'; END IF;
 items:=jsonb_build_array(jsonb_build_object('menu_id',910001,'quantity',1,'price',20000,'note','Second batch only'));
 r:=public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token2,'request_id','30000000-0000-4000-8000-000000000003','items',items));batch2:=(r->>'id')::uuid;
 r:=public.qr_staff_v1(a,'accept',jsonb_build_object('branch_id',branch,'batch_id',batch2));
 IF r->>'sequence'<>'2' OR (SELECT stock_sisa FROM public.get_menu_stock_today(branch) WHERE menu_name_key='fixture rice')<>4 THEN RAISE EXCEPTION 'QRTEST: additional batch reservation'; END IF;
 job:='40000000-0000-4000-8000-000000000001';
 r:=public.qr_staff_v1(a,'begin_print',jsonb_build_object('branch_id',branch,'batch_id',batch2,'attempt_id',job));
 IF r->>'copy'<>'false' OR r->>'sequence'<>'2' OR jsonb_array_length(r->'items')<>1 OR r->'items'->0->>'quantity'<>'1' THEN RAISE EXCEPTION 'QRTEST: kitchen ticket duplicated first batch'; END IF;
 again:=public.qr_staff_v1(a,'begin_print',jsonb_build_object('branch_id',branch,'batch_id',batch2,'attempt_id',job));
 IF again->>'copy'<>'true' THEN RAISE EXCEPTION 'QRTEST: uncertain print retry not marked copy'; END IF;
 r:=public.qr_staff_v1(a,'finish_print',jsonb_build_object('branch_id',branch,'batch_id',batch2,'attempt_id',job,'success',true));
 IF (SELECT state FROM zela_qr.print_jobs WHERE id=job)<>'success' THEN RAISE EXCEPTION 'QRTEST: print acknowledgement'; END IF;
 r:=public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token,'request_id','30000000-0000-4000-8000-000000000004','items',items));pending_batch:=(r->>'id')::uuid;
 denied:=false;BEGIN PERFORM public.qr_staff_v1(a,'bill',jsonb_build_object('branch_id',branch,'visit_id',visit,'device_id',repeat('d',64)));EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: pending batch omitted from bill'; END IF;
 r:=public.qr_staff_v1(a,'reject',jsonb_build_object('branch_id',branch,'batch_id',pending_batch,'reason','Fixture rejection'));
 bill:=public.qr_staff_v1(a,'bill',jsonb_build_object('branch_id',branch,'visit_id',visit,'device_id',repeat('d',64)));
 again:=public.qr_staff_v1(a,'bill',jsonb_build_object('branch_id',branch,'visit_id',visit,'device_id',repeat('d',64)));
 IF bill->>'bill_token'<>again->>'bill_token' OR jsonb_array_length(bill->'items')<>2 THEN RAISE EXCEPTION 'QRTEST: bill retry changed'; END IF;
 denied:=false;BEGIN PERFORM public.qr_staff_v1(a,'bill',jsonb_build_object('branch_id',branch,'visit_id',visit,'device_id',repeat('e',64)));EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: two devices billing'; END IF;
 IF public.get_qr_bill_stock_v1(visit,(bill->>'bill_token')::uuid)->0->>'stock_sisa'<>'10' THEN RAISE EXCEPTION 'QRTEST: own reservation double counted'; END IF;
 denied:=false;BEGIN PERFORM public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token,'request_id','30000000-0000-4000-8000-000000000005','items',items));EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: additions while paying'; END IF;
 SELECT balance INTO old_balance FROM public.subscriptions WHERE owner_id='10000000-0000-4000-8000-000000000001';
 manual:=jsonb_build_object('version',1,'account_id',a,'branch_id',branch,'order_number','FIXTURE-MANUAL-1','created_at',now(),
 'payment_method','cash','subtotal',60000,'discount',0,'tax',0,'service_charge_amount',0,'total',60000,'paid_amount',60000,'change_amount',0,
 'items',jsonb_build_array(jsonb_build_object('item_name','Fixture dish','quantity',3,'price',20000,'subtotal',60000)));
 denied:=false;BEGIN PERFORM public.sync_paid_food_order(manual);EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=true;END;
 IF NOT denied OR EXISTS(SELECT 1 FROM public.orders) OR (SELECT stock_sisa FROM public.menu_stock LIMIT 1)<>10
 OR (SELECT balance FROM public.subscriptions WHERE owner_id='10000000-0000-4000-8000-000000000001')<>old_balance THEN RAISE EXCEPTION 'QRTEST: failed POS sale modified money/stock'; END IF;
 manual:=manual||jsonb_build_object('subtotal',20000,'total',20000,'paid_amount',20000,'items',jsonb_build_array(jsonb_build_object('item_name','Fixture dish','quantity',1,'price',20000,'subtotal',20000)));
 r:=public.sync_paid_food_order(manual);again:=public.sync_paid_food_order(manual);
 IF r->>'success'<>'true' OR r->>'order_id'<>again->>'order_id' OR (SELECT stock_sisa FROM public.menu_stock LIMIT 1)<>8 THEN RAISE EXCEPTION 'QRTEST: ordinary POS regression/idempotency'; END IF;
 payload:=jsonb_build_object('version',1,'account_id',a,'branch_id',branch,'order_number',bill->>'receipt_number','created_at',now(),
 'payment_method','cash','subtotal',60000,'discount',0,'tax',0,'service_charge_amount',0,'total',60000,'paid_amount',60000,'change_amount',0,
 'qr_visit_id',visit,'qr_bill_token',bill->>'bill_token',
 'items',jsonb_build_array(jsonb_build_object('item_name','Fixture dish','quantity',3,'price',20000,'subtotal',60000)));
 denied:=false;BEGIN PERFORM public.sync_qr_food_order_v1(payload||jsonb_build_object('items','[]'::jsonb));EXCEPTION WHEN SQLSTATE '22023' THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: altered bill accepted'; END IF;
 r:=public.sync_qr_food_order_v1(payload);again:=public.sync_qr_food_order_v1(payload);
 IF r->>'success'<>'true' OR r->>'order_id'<>again->>'order_id' OR (SELECT state FROM zela_qr.visits WHERE id=visit)<>'paid'
 OR (SELECT stock_sisa FROM public.menu_stock LIMIT 1)<>2 OR (SELECT count(*) FROM public.orders)<>2
 OR (SELECT status FROM public.restaurant_tables WHERE id=910001)<>'empty' THEN RAISE EXCEPTION 'QRTEST: combined settlement not exactly once'; END IF;
 r:=public.qr_guest_v1('status',jsonb_build_object('link_token',link,'guest_token',token,'visit_id',visit));
 IF r->>'state'<>'paid' THEN RAISE EXCEPTION 'QRTEST: own paid status inaccessible'; END IF;
 r:=public.qr_staff_v1(a,'open',jsonb_build_object('branch_id',branch,'table_id',910001));visit:=(r->>'visit_id')::uuid;
 denied:=false;BEGIN PERFORM public.qr_guest_v1('status',jsonb_build_object('link_token',link,'guest_token',token));EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'QRTEST: customer session carried into next visit'; END IF;
 r:=public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token2,'name','Fixture new visit'));
 r:=public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token2,'request_id','30000000-0000-4000-8000-000000000006','items',items));batch:=(r->>'id')::uuid;
 r:=public.qr_staff_v1(a,'accept',jsonb_build_object('branch_id',branch,'batch_id',batch));
 r:=public.qr_staff_v1(a,'cancel',jsonb_build_object('branch_id',branch,'batch_id',batch,'reason','Fixture cancellation'));
 IF (SELECT stock_sisa FROM public.get_menu_stock_today(branch) WHERE menu_name_key='fixture rice')<>2 THEN RAISE EXCEPTION 'QRTEST: cancellation did not release reserve'; END IF;
 r:=public.qr_staff_v1(a,'begin_print',jsonb_build_object('branch_id',branch,'batch_id',batch,'attempt_id','40000000-0000-4000-8000-000000000002'));
 IF r->>'cancelled'<>'true' THEN RAISE EXCEPTION 'QRTEST: cancellation ticket missing'; END IF;
 r:=public.qr_staff_v1(a,'close_empty',jsonb_build_object('branch_id',branch,'visit_id',visit));
 IF r->>'closed'<>'true' THEN RAISE EXCEPTION 'QRTEST: empty visit close'; END IF;
 INSERT INTO public.customers(id,owner_id,no_hp,nama,member_number,member_registered_at)
 VALUES('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','0800000000','Fixture member','123456',now()-interval '1 minute');
 r:=public.qr_staff_v1(a,'open',jsonb_build_object('branch_id',branch,'table_id',910001));visit:=(r->>'visit_id')::uuid;
 r:=public.qr_guest_v1('join',jsonb_build_object('link_token',link,'guest_token',token,'name','Fixture member'));
 r:=public.qr_guest_v1('submit',jsonb_build_object('link_token',link,'guest_token',token,'request_id','30000000-0000-4000-8000-000000000007','items',items));
 r:=public.qr_staff_v1(a,'accept',jsonb_build_object('branch_id',branch,'batch_id',r->>'id'));
 bill:=public.qr_staff_v1(a,'bill',jsonb_build_object('branch_id',branch,'visit_id',visit,'device_id',repeat('d',64)));
 payload:=payload||jsonb_build_object('qr_visit_id',visit,'qr_bill_token',bill->>'bill_token','order_number',bill->>'receipt_number',
 'subtotal',20000,'total',20000,'paid_amount',20000,'order_type','dine_in','member_number','123456','customer_id','50000000-0000-4000-8000-000000000001',
 'items',jsonb_build_array(jsonb_build_object('item_name','Fixture dish','quantity',1,'price',20000,'subtotal',20000)));
 r:=public.sync_qr_food_order_v1(payload);again:=public.sync_qr_food_order_v1(payload);
 IF r->>'member_linked'<>'true' OR r->>'qr_billed'<>'true' OR r->>'order_id'<>again->>'order_id'
 OR (SELECT total_transaksi FROM public.customers WHERE id='50000000-0000-4000-8000-000000000001')<>1 THEN RAISE EXCEPTION 'QRTEST: member settlement duplicated or lost'; END IF;
 RAISE NOTICE 'QRTEST: PASS catalog privacy; duplicate retries; tenant scope; reservation; delta tickets; uncertain-print copy; bill lock; ordinary POS rollback; combined payment exactly once; visit reset; cancellation';
END;
$test$;
ROLLBACK;
