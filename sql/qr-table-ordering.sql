-- QR dine-in: additive private ledger, service-only guest/staff API, existing POS settlement.
BEGIN;
SET LOCAL lock_timeout='3s';
CREATE SCHEMA zela_qr AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA zela_qr FROM PUBLIC,anon,authenticated;
CREATE TABLE zela_qr.links(
 table_id bigint PRIMARY KEY REFERENCES public.restaurant_tables(id),
 token text NOT NULL UNIQUE DEFAULT encode(extensions.gen_random_bytes(32),'hex'),
 enabled boolean NOT NULL DEFAULT true
);
CREATE TABLE zela_qr.visits(
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 table_id bigint NOT NULL REFERENCES zela_qr.links(table_id),
 branch_id uuid NOT NULL REFERENCES public.branches(id),
 state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','closing','paid','cancelled')),
 created_at timestamptz NOT NULL DEFAULT now(), closed_at timestamptz,
 bill_device text, bill_token uuid, bill_actor uuid, receipt_number text, settlement jsonb
);
CREATE UNIQUE INDEX qr_one_live_visit ON zela_qr.visits(table_id) WHERE state IN ('open','closing');
CREATE TABLE zela_qr.guests(
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 visit_id uuid NOT NULL REFERENCES zela_qr.visits(id),
 token_hash text NOT NULL, name text NOT NULL CHECK(length(name) BETWEEN 1 AND 60),
 member_number text CHECK(member_number IS NULL OR member_number ~ '^[0-9]{6}$'),
 UNIQUE(visit_id,token_hash)
);
CREATE TABLE zela_qr.batches(
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 visit_id uuid NOT NULL REFERENCES zela_qr.visits(id),
 guest_id uuid NOT NULL REFERENCES zela_qr.guests(id),
 request_id uuid NOT NULL, request_body jsonb NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','accepted','rejected','cancelled')),
 items jsonb NOT NULL, reason text, kitchen_sequence integer,
 created_at timestamptz NOT NULL DEFAULT now(), accepted_at timestamptz,
 UNIQUE(guest_id,request_id), UNIQUE(visit_id,kitchen_sequence)
);
CREATE TABLE zela_qr.print_jobs(
 id uuid PRIMARY KEY, batch_id uuid NOT NULL REFERENCES zela_qr.batches(id),
 kind text NOT NULL CHECK(kind IN ('order','cancel')),
 state text NOT NULL DEFAULT 'claimed' CHECK(state IN ('claimed','success','failed')),
 actor uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX qr_batches_visit ON zela_qr.batches(visit_id,state);
CREATE INDEX qr_print_batch ON zela_qr.print_jobs(batch_id,kind);
ALTER TABLE zela_qr.links ENABLE ROW LEVEL SECURITY;
ALTER TABLE zela_qr.visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE zela_qr.guests ENABLE ROW LEVEL SECURITY;
ALTER TABLE zela_qr.batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE zela_qr.print_jobs ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION zela_qr.stock(p_branch uuid) RETURNS TABLE(name text,remaining numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT DISTINCT ON (s.menu_name_key) s.menu_name_key,s.stock_sisa
 FROM public.menu_stock s WHERE s.branch_id=p_branch
 AND s.stock_date <= (now() AT TIME ZONE 'Asia/Jakarta')::date
 AND (s.stock_date=(now() AT TIME ZONE 'Asia/Jakarta')::date OR EXISTS(
  SELECT 1 FROM public.stock_skip_items i WHERE i.branch_id=p_branch
  AND lower(btrim(i.bahan_name))=s.menu_name_key))
 ORDER BY s.menu_name_key,s.stock_date DESC,s.updated_at DESC NULLS LAST,s.id;
$$;
CREATE FUNCTION zela_qr.needs(p_branch uuid,p_items jsonb)
RETURNS TABLE(name text,quantity numeric) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH items AS(SELECT lower(btrim(x->>'item_name')) AS name,sum((x->>'quantity')::numeric) AS qty
 FROM jsonb_array_elements(p_items) x GROUP BY 1), components AS(
 SELECT lower(btrim(c.component_key)) AS name,i.qty*c.qty_per_order AS qty
 FROM items i JOIN public.menu_stock_components c ON c.branch_id=p_branch
 AND lower(btrim(c.menu_name_key))=i.name), direct AS(
 SELECT i.name,i.qty FROM items i WHERE
 (EXISTS(SELECT 1 FROM zela_qr.stock(p_branch) s WHERE s.name=i.name)
 OR NOT EXISTS(SELECT 1 FROM public.menu_stock_components c WHERE c.branch_id=p_branch AND lower(btrim(c.menu_name_key))=i.name))
 AND NOT EXISTS(SELECT 1 FROM public.menu_stock_components c WHERE c.branch_id=p_branch
 AND lower(btrim(c.menu_name_key))=i.name AND lower(btrim(c.component_key))=i.name))
 SELECT n.name,sum(n.qty) FROM(SELECT * FROM components UNION ALL SELECT * FROM direct)n GROUP BY n.name;
$$;
CREATE FUNCTION zela_qr.reserved(p_branch uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(jsonb_agg(x.item),'[]'::jsonb) FROM zela_qr.batches b
 JOIN zela_qr.visits v ON v.id=b.visit_id
 CROSS JOIN LATERAL jsonb_array_elements(b.items)x(item)
 WHERE v.branch_id=p_branch AND v.state IN ('open','closing') AND b.state='accepted';
$$;
CREATE FUNCTION zela_qr.assert_capacity(p_branch uuid,p_items jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n record; available numeric; used numeric;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.menu_stock_components WHERE branch_id=p_branch)
 AND NOT EXISTS(SELECT 1 FROM zela_qr.stock(p_branch)) THEN RETURN; END IF;
 FOR n IN SELECT * FROM zela_qr.needs(p_branch,p_items) LOOP
  SELECT s.remaining INTO available FROM zela_qr.stock(p_branch)s WHERE s.name=n.name;
  SELECT coalesce(sum(r.quantity),0) INTO used FROM zela_qr.needs(p_branch,zela_qr.reserved(p_branch))r WHERE r.name=n.name;
  IF n.quantity IS NULL OR n.quantity<=0 OR available IS NULL OR available='NaN'::numeric
     OR available-used<n.quantity THEN
   RAISE EXCEPTION 'Stok bahan tidak cukup atau belum diset' USING ERRCODE='P0001';
  END IF;
 END LOOP;
END;
$$;
CREATE FUNCTION zela_qr.assert_reserved(p_branch uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n record; available numeric;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.menu_stock_components WHERE branch_id=p_branch)
 AND NOT EXISTS(SELECT 1 FROM zela_qr.stock(p_branch)) THEN RETURN; END IF;
 FOR n IN SELECT * FROM zela_qr.needs(p_branch,zela_qr.reserved(p_branch)) LOOP
  SELECT s.remaining INTO available FROM zela_qr.stock(p_branch)s WHERE s.name=n.name;
  IF available IS NULL OR available='NaN'::numeric OR available<n.quantity THEN
   RAISE EXCEPTION 'Stok sudah dipesan melalui QR. Perbarui stok dan pesanan.' USING ERRCODE='P0001';
  END IF;
 END LOOP;
END;
$$;
CREATE FUNCTION zela_qr.assert_actor(p_actor uuid,p_branch uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated')::text,true);
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE auth_id=p_actor AND is_active IS TRUE
 AND is_approved IS TRUE AND role IN ('kasir','owner','manajer','admin','superadmin')) THEN
  RAISE EXCEPTION 'Akun kasir tidak aktif' USING ERRCODE='42501'; END IF;
 PERFORM public.v54_assert_branch(p_branch);
 IF NOT EXISTS(SELECT 1 FROM public.users u JOIN public.branches b ON b.id=p_branch
  WHERE u.auth_id=p_actor AND (u.role='superadmin' OR (u.owner_id=b.owner_id
   AND (u.role IN ('owner','admin') OR u.branch_id=b.id)))) THEN
  RAISE EXCEPTION 'Akses cabang ditolak' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.branches b JOIN public.owners o ON o.id=b.owner_id
 WHERE b.id=p_branch AND b.is_active IS TRUE AND b.mode='food' AND o.is_active IS TRUE) THEN
  RAISE EXCEPTION 'Cabang tidak aktif' USING ERRCODE='42501'; END IF;
END;
$$;

CREATE FUNCTION zela_qr.catalog(p_branch uuid,p_open boolean) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH stock AS MATERIALIZED(SELECT * FROM zela_qr.stock(p_branch)),
 held AS MATERIALIZED(SELECT * FROM zela_qr.needs(p_branch,zela_qr.reserved(p_branch))),
 menus AS MATERIALIZED(SELECT m.*,lower(btrim(m.name)) AS key FROM public.menu_items m
  WHERE m.branch_id=p_branch AND m.is_available IS TRUE AND m.is_ingredient IS NOT TRUE ORDER BY m.sort_order,m.name LIMIT 500),
 components AS MATERIALIZED(SELECT lower(btrim(menu_name_key)) AS menu,lower(btrim(component_key)) AS ingredient,qty_per_order AS qty
  FROM public.menu_stock_components WHERE branch_id=p_branch),
 requirements AS(SELECT m.id,c.ingredient AS name,c.qty FROM menus m JOIN components c ON c.menu=m.key
  UNION ALL SELECT m.id,m.key,1::numeric FROM menus m
  WHERE (EXISTS(SELECT 1 FROM stock s WHERE s.name=m.key) OR NOT EXISTS(SELECT 1 FROM components c WHERE c.menu=m.key))
  AND NOT EXISTS(SELECT 1 FROM components c WHERE c.menu=m.key AND c.ingredient=m.key)),
 required AS(SELECT id,name,sum(qty) AS qty FROM requirements GROUP BY id,name),
 availability AS(SELECT n.id,bool_and(n.qty>0 AND n.qty<>'NaN'::numeric AND s.remaining IS NOT NULL
  AND s.remaining<>'NaN'::numeric AND s.remaining-coalesce(h.quantity,0)>=n.qty) AS available
  FROM required n LEFT JOIN stock s ON s.name=n.name LEFT JOIN held h ON h.name=n.name GROUP BY n.id),
 enforced AS(SELECT EXISTS(SELECT 1 FROM components) OR EXISTS(SELECT 1 FROM stock) AS value)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'description',m.description,'price',m.price,
  'available',p_open AND (NOT e.value OR coalesce(a.available,false))) ORDER BY m.sort_order,m.name),'[]')
 FROM menus m CROSS JOIN enforced e LEFT JOIN availability a ON a.id=m.id;
$$;

CREATE FUNCTION public.qr_guest_v1(p_action text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t record; v zela_qr.visits; g zela_qr.guests; b zela_qr.batches;
 m record; x jsonb; lines jsonb:='[]'; menus jsonb:='[]'; request_body jsonb;
 visitor_hash text; available boolean; total_qty integer:=0;
BEGIN
 IF p_action NOT IN ('menu','join','submit','status') OR length(coalesce(p_data->>'link_token',''))<>64 THEN
 RAISE EXCEPTION 'QR tidak valid' USING ERRCODE='22023'; END IF;
 SELECT r.id,r.branch_id,r.name,br.name AS branch_name,br.ppn_enabled,br.ppn_persen,br.sc_enabled,br.sc_amount,br.rounding INTO t FROM zela_qr.links l
 JOIN public.restaurant_tables r ON r.id=l.table_id JOIN public.branches br ON br.id=r.branch_id
 JOIN public.owners o ON o.id=br.owner_id WHERE l.token=p_data->>'link_token' AND l.enabled
 AND r.is_active IS TRUE AND br.is_active IS TRUE AND br.mode='food' AND o.is_active IS TRUE;
 IF NOT FOUND THEN RAISE EXCEPTION 'QR tidak tersedia' USING ERRCODE='22023'; END IF;
 IF p_action='status' AND nullif(p_data->>'visit_id','') IS NOT NULL THEN
  SELECT * INTO v FROM zela_qr.visits WHERE id=(p_data->>'visit_id')::uuid AND table_id=t.id;
 ELSE
  SELECT * INTO v FROM zela_qr.visits WHERE table_id=t.id AND state IN ('open','closing');
 END IF;
 IF p_action='menu' THEN
  RETURN jsonb_build_object('branch',t.branch_name,'table',t.name,'visit_id',v.id,'state',coalesce(v.state,'closed'),
   'menu',zela_qr.catalog(t.branch_id,coalesce(v.state='open',false)),
   'fees',jsonb_build_object('tax_enabled',t.ppn_enabled,'tax_percent',t.ppn_persen,'service_enabled',t.sc_enabled,'service_amount',t.sc_amount,'rounding',t.rounding));
 END IF;
 IF v.id IS NULL THEN RAISE EXCEPTION 'Meja belum dibuka kasir' USING ERRCODE='P0001'; END IF;
 SELECT * INTO v FROM zela_qr.visits WHERE id=v.id FOR UPDATE;
 IF length(coalesce(p_data->>'guest_token',''))<>64 THEN RAISE EXCEPTION 'Sesi pelanggan tidak valid' USING ERRCODE='22023'; END IF;
 visitor_hash:=encode(extensions.digest(p_data->>'guest_token','sha256'),'hex');
 SELECT * INTO g FROM zela_qr.guests WHERE visit_id=v.id AND token_hash=visitor_hash;
 IF p_action='join' THEN
  IF v.state<>'open' THEN RAISE EXCEPTION 'Tagihan sedang disiapkan' USING ERRCODE='P0001'; END IF;
  IF length(btrim(coalesce(p_data->>'name',''))) NOT BETWEEN 1 AND 60 OR (p_data->>'name') ~ '[[:cntrl:]]'
  OR (nullif(p_data->>'member_number','') IS NOT NULL AND p_data->>'member_number' !~ '^[0-9]{6}$') THEN
   RAISE EXCEPTION 'Nama atau kode member tidak valid' USING ERRCODE='22023'; END IF;
  IF g.id IS NULL THEN
   IF (SELECT count(*) FROM zela_qr.guests WHERE visit_id=v.id)>=50 THEN RAISE EXCEPTION 'Hubungi kasir' USING ERRCODE='P0001'; END IF;
   INSERT INTO zela_qr.guests(visit_id,token_hash,name,member_number) VALUES(v.id,visitor_hash,btrim(p_data->>'name'),nullif(p_data->>'member_number','')) RETURNING * INTO g;
  END IF;
  RETURN jsonb_build_object('joined',true,'name',g.name,'visit_id',v.id);
 END IF;
 IF g.id IS NULL THEN RAISE EXCEPTION 'Isi nama terlebih dahulu' USING ERRCODE='42501'; END IF;
 IF p_action='status' THEN
  RETURN jsonb_build_object('state',v.state,'orders',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'id',q.id,'request_id',q.request_id,'state',q.state,'reason',q.reason,'sequence',q.kitchen_sequence,'items',q.items,'created_at',q.created_at)
   ORDER BY q.created_at) FROM zela_qr.batches q WHERE q.guest_id=g.id),'[]'::jsonb));
 END IF;
 request_body:=p_data->'items';
 SELECT * INTO b FROM zela_qr.batches WHERE guest_id=g.id AND request_id=(p_data->>'request_id')::uuid;
 IF FOUND THEN
  IF b.request_body IS DISTINCT FROM request_body THEN RAISE EXCEPTION 'Kode kiriman sudah digunakan' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('id',b.id,'state',b.state,'already_received',true);
 END IF;
 IF v.state<>'open' THEN RAISE EXCEPTION 'Tagihan sedang disiapkan' USING ERRCODE='P0001'; END IF;
 IF jsonb_typeof(request_body) IS DISTINCT FROM 'array' OR jsonb_array_length(request_body) NOT BETWEEN 1 AND 20 THEN
  RAISE EXCEPTION 'Keranjang tidak valid' USING ERRCODE='22023'; END IF;
 IF (SELECT count(*) FROM zela_qr.batches WHERE guest_id=g.id AND state='pending')>=3 THEN
  RAISE EXCEPTION 'Tunggu kasir menerima pesanan sebelumnya' USING ERRCODE='P0001'; END IF;
 IF (SELECT count(*) FROM zela_qr.batches WHERE visit_id=v.id)>=200 THEN RAISE EXCEPTION 'Hubungi kasir' USING ERRCODE='P0001'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(request_body) LOOP
  IF jsonb_typeof(x->'quantity') IS DISTINCT FROM 'number' OR (x->>'quantity') !~ '^[0-9]{1,2}$'
  OR (x->>'quantity')::integer NOT BETWEEN 1 AND 50 OR length(coalesce(x->>'note',''))>240
  OR coalesce(x->>'note','') ~ '[[:cntrl:]]' THEN
   RAISE EXCEPTION 'Jumlah atau catatan tidak valid' USING ERRCODE='22023'; END IF;
  SELECT id,name,price INTO m FROM public.menu_items WHERE id=(x->>'menu_id')::bigint
   AND branch_id=t.branch_id AND is_available IS TRUE AND is_ingredient IS NOT TRUE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Menu tidak tersedia' USING ERRCODE='P0001'; END IF;
  IF m.price IS DISTINCT FROM (x->>'price')::numeric THEN RAISE EXCEPTION 'Harga berubah. Muat ulang menu.' USING ERRCODE='P0001'; END IF;
  total_qty:=total_qty+(x->>'quantity')::integer;
  lines:=lines||jsonb_build_array(jsonb_build_object('menu_id',m.id,'item_name',m.name,'price',m.price,
   'quantity',(x->>'quantity')::integer,'note',btrim(coalesce(x->>'note',''))));
 END LOOP;
 IF total_qty>50 THEN RAISE EXCEPTION 'Maksimal 50 porsi per kiriman' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('zela-food-sync:'||t.branch_id::text,0));
 PERFORM zela_qr.assert_capacity(t.branch_id,lines);
 INSERT INTO zela_qr.batches(visit_id,guest_id,request_id,request_body,items)
 VALUES(v.id,g.id,(p_data->>'request_id')::uuid,request_body,lines) RETURNING * INTO b;
 RETURN jsonb_build_object('id',b.id,'state',b.state);
END;
$$;

CREATE FUNCTION public.qr_staff_v1(p_actor uuid,p_action text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
#variable_conflict use_column
DECLARE branch uuid:=(p_data->>'branch_id')::uuid; t public.restaurant_tables;
 v zela_qr.visits; b zela_qr.batches; j zela_qr.print_jobs; link zela_qr.links;
 lines jsonb; sequence_no integer; copy_ticket boolean:=false;
BEGIN
 PERFORM zela_qr.assert_actor(p_actor,branch);
 IF p_action='count' THEN
  RETURN (SELECT jsonb_build_object('count',count(*),'latest',max(b.created_at)) FROM zela_qr.batches b
   JOIN zela_qr.visits v ON v.id=b.visit_id WHERE v.branch_id=branch AND v.state='open' AND b.state='pending');
 END IF;
 IF p_action='list' THEN
  RETURN jsonb_build_object('tables',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'id',r.id,'name',r.name,'enabled',coalesce(l.enabled,false),'token',l.token,
   'visit_id',v.id,'state',coalesce(v.state,'closed')) ORDER BY r.name)
   FROM public.restaurant_tables r LEFT JOIN zela_qr.links l ON l.table_id=r.id
   LEFT JOIN zela_qr.visits v ON v.table_id=r.id AND v.state IN ('open','closing')
   WHERE r.branch_id=branch AND r.is_active IS TRUE),'[]'::jsonb),
   'orders',coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'visit_id',v.id,'table_id',r.id,
    'table_name',r.name,'name',g.name,'member_number',g.member_number,'state',b.state,'items',b.items,
    'sequence',b.kitchen_sequence,'created_at',b.created_at,'reason',b.reason,
    'print_success',EXISTS(SELECT 1 FROM zela_qr.print_jobs p WHERE p.batch_id=b.id AND p.state='success' AND p.kind='order'))
    ORDER BY b.created_at) FROM zela_qr.batches b JOIN zela_qr.visits v ON v.id=b.visit_id
    JOIN public.restaurant_tables r ON r.id=v.table_id JOIN zela_qr.guests g ON g.id=b.guest_id
    WHERE v.branch_id=branch AND v.state IN ('open','closing')),'[]'::jsonb));
 END IF;
 IF p_action IN ('enable','open') THEN
  SELECT * INTO t FROM public.restaurant_tables WHERE id=(p_data->>'table_id')::bigint AND branch_id=branch AND is_active IS TRUE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Meja tidak ditemukan' USING ERRCODE='22023'; END IF;
  INSERT INTO zela_qr.links(table_id) VALUES(t.id) ON CONFLICT(table_id) DO UPDATE SET enabled=true RETURNING * INTO link;
  IF p_action='enable' THEN RETURN jsonb_build_object('token',link.token,'table_id',t.id); END IF;
  SELECT * INTO v FROM zela_qr.visits WHERE table_id=t.id AND state IN ('open','closing');
  IF v.id IS NULL THEN
   IF t.status<>'empty' OR EXISTS(SELECT 1 FROM public.table_carts WHERE branch_id=branch AND table_id=t.id) THEN
    RAISE EXCEPTION 'Selesaikan pesanan meja lama terlebih dahulu' USING ERRCODE='P0001'; END IF;
   INSERT INTO zela_qr.visits(table_id,branch_id) VALUES(t.id,branch) RETURNING * INTO v;
   UPDATE public.restaurant_tables SET status='occupied',occupied_at=now(),customer_name='Pesanan QR' WHERE id=t.id;
  END IF;
  RETURN jsonb_build_object('visit_id',v.id,'state',v.state,'token',link.token);
 END IF;
 IF p_action IN ('accept','reject','cancel','begin_print','finish_print') THEN
  SELECT * INTO b FROM zela_qr.batches WHERE id=(p_data->>'batch_id')::uuid;
  IF b.id IS NULL THEN RAISE EXCEPTION 'Pesanan tidak ditemukan' USING ERRCODE='22023'; END IF;
  SELECT * INTO v FROM zela_qr.visits WHERE id=b.visit_id AND branch_id=branch FOR UPDATE;
 ELSE
  SELECT * INTO v FROM zela_qr.visits WHERE id=(p_data->>'visit_id')::uuid AND branch_id=branch FOR UPDATE;
 END IF;
 IF v.id IS NULL THEN RAISE EXCEPTION 'Akses meja ditolak' USING ERRCODE='42501'; END IF;
 IF p_action='accept' THEN
  IF b.state='accepted' THEN RETURN jsonb_build_object('accepted',true,'already_received',true); END IF;
  IF v.state<>'open' OR b.state<>'pending' THEN RAISE EXCEPTION 'Pesanan sudah diproses' USING ERRCODE='P0001'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('zela-food-sync:'||branch::text,0));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(b.items)i LEFT JOIN public.menu_items m
   ON m.id=(i->>'menu_id')::bigint AND m.branch_id=branch
   WHERE m.id IS NULL OR m.is_available IS NOT TRUE OR m.is_ingredient IS TRUE OR m.price IS DISTINCT FROM (i->>'price')::numeric) THEN
    RAISE EXCEPTION 'Menu/harga berubah. Tolak dan minta pelanggan memesan ulang.' USING ERRCODE='P0001'; END IF;
  PERFORM zela_qr.assert_capacity(branch,b.items);
  SELECT coalesce(max(kitchen_sequence),0)+1 INTO sequence_no FROM zela_qr.batches WHERE visit_id=v.id;
  UPDATE zela_qr.batches SET state='accepted',accepted_at=now(),kitchen_sequence=sequence_no WHERE id=b.id;
  RETURN jsonb_build_object('accepted',true,'sequence',sequence_no);
 ELSIF p_action IN ('reject','cancel') THEN
  IF v.state<>'open' OR b.state<>(CASE WHEN p_action='reject' THEN 'pending' ELSE 'accepted' END)
   OR length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 1 AND 200 THEN
   RAISE EXCEPTION 'Alasan atau status pesanan tidak valid' USING ERRCODE='P0001'; END IF;
  UPDATE zela_qr.batches SET state=CASE WHEN p_action='reject' THEN 'rejected' ELSE 'cancelled' END,
   reason=btrim(p_data->>'reason') WHERE id=b.id;
  RETURN jsonb_build_object('success',true);
 ELSIF p_action='begin_print' THEN
  IF b.state NOT IN ('accepted','cancelled') THEN RAISE EXCEPTION 'Pesanan belum diterima' USING ERRCODE='P0001'; END IF;
  SELECT * INTO j FROM zela_qr.print_jobs WHERE id=(p_data->>'attempt_id')::uuid;
  IF j.id IS NOT NULL THEN
   IF j.batch_id<>b.id OR j.actor<>p_actor THEN RAISE EXCEPTION 'Percobaan cetak tidak valid' USING ERRCODE='42501'; END IF;
   copy_ticket:=true;
  ELSE
   copy_ticket:=EXISTS(SELECT 1 FROM zela_qr.print_jobs WHERE batch_id=b.id AND kind=CASE WHEN b.state='cancelled' THEN 'cancel' ELSE 'order' END);
   INSERT INTO zela_qr.print_jobs(id,batch_id,kind,actor) VALUES((p_data->>'attempt_id')::uuid,b.id,CASE WHEN b.state='cancelled' THEN 'cancel' ELSE 'order' END,p_actor) RETURNING * INTO j;
  END IF;
  RETURN jsonb_build_object('attempt_id',j.id,'copy',copy_ticket,'cancelled',b.state='cancelled','sequence',b.kitchen_sequence,
   'table',(SELECT name FROM public.restaurant_tables WHERE id=v.table_id),'customer',(SELECT name FROM zela_qr.guests WHERE id=b.guest_id),
   'created_at',b.created_at,'items',b.items,'reason',b.reason);
 ELSIF p_action='finish_print' THEN
  UPDATE zela_qr.print_jobs SET state=CASE WHEN p_data->>'success'='true' THEN 'success' ELSE 'failed' END
   WHERE id=(p_data->>'attempt_id')::uuid AND batch_id=b.id AND actor=p_actor AND state='claimed';
  RETURN jsonb_build_object('success',true);
 ELSIF p_action='close_empty' THEN
  IF v.state<>'open' OR EXISTS(SELECT 1 FROM zela_qr.batches WHERE visit_id=v.id AND state IN ('pending','accepted')) THEN
   RAISE EXCEPTION 'Selesaikan pesanan/tagihan terlebih dahulu' USING ERRCODE='P0001'; END IF;
  UPDATE zela_qr.visits SET state='cancelled',closed_at=now() WHERE id=v.id;
  UPDATE public.restaurant_tables SET status='empty',customer_name=NULL,occupied_at=NULL WHERE id=v.table_id;
  RETURN jsonb_build_object('closed',true);
 ELSIF p_action='bill' THEN
  IF v.state NOT IN ('open','closing') OR length(coalesce(p_data->>'device_id','')) NOT BETWEEN 32 AND 80 THEN
   RAISE EXCEPTION 'Sesi pembayaran tidak valid' USING ERRCODE='P0001'; END IF;
  IF EXISTS(SELECT 1 FROM zela_qr.batches WHERE visit_id=v.id AND state='pending') THEN
   RAISE EXCEPTION 'Terima atau tolak semua pesanan sebelum menagih' USING ERRCODE='P0001'; END IF;
  SELECT jsonb_agg(i) INTO lines FROM zela_qr.batches b CROSS JOIN LATERAL jsonb_array_elements(b.items)i WHERE b.visit_id=v.id AND b.state='accepted';
  IF lines IS NULL THEN RAISE EXCEPTION 'Belum ada pesanan diterima' USING ERRCODE='P0001'; END IF;
  IF v.state='closing' AND (v.bill_device<>p_data->>'device_id' OR v.bill_actor<>p_actor) THEN
   RAISE EXCEPTION 'Pembayaran sedang ditangani kasir/perangkat lain' USING ERRCODE='P0001'; END IF;
  IF v.state='open' THEN
   UPDATE zela_qr.visits SET state='closing',bill_device=p_data->>'device_id',bill_actor=p_actor,
    bill_token=extensions.gen_random_uuid(),receipt_number='QR-'||replace(id::text,'-','') WHERE id=v.id RETURNING * INTO v;
  END IF;
  RETURN jsonb_build_object('visit_id',v.id,'bill_token',v.bill_token,'receipt_number',v.receipt_number,
   'branch_id',v.branch_id,'table_name',(SELECT name FROM public.restaurant_tables WHERE id=v.table_id),'items',lines);
 END IF;
 RAISE EXCEPTION 'Aksi tidak dikenal' USING ERRCODE='22023';
END;
$$;

-- All restaurant POS receipts share the same branch lock and respect accepted QR reservations.
ALTER FUNCTION public.get_menu_stock_today(uuid) RENAME TO get_menu_stock_today_before_qr_v1;
CREATE FUNCTION public.get_menu_stock_today(p_branch_id uuid)
RETURNS TABLE(id uuid,menu_item_id integer,menu_name text,menu_name_key text,stock_awal numeric,
 stock_terjual numeric,stock_sisa numeric,min_alert numeric,updated_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.v54_assert_branch(p_branch_id);
 RETURN QUERY SELECT s.id,s.menu_item_id,s.menu_name,s.menu_name_key,s.stock_awal,s.stock_terjual,
 s.stock_sisa-coalesce(n.quantity,0),s.min_alert,s.updated_at
 FROM public.get_menu_stock_today_before_qr_v1(p_branch_id)s
 LEFT JOIN zela_qr.needs(p_branch_id,zela_qr.reserved(p_branch_id))n ON n.name=s.menu_name_key;
END;
$$;
REVOKE ALL ON FUNCTION public.get_menu_stock_today(uuid),public.get_menu_stock_today_before_qr_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_menu_stock_today(uuid) TO authenticated,service_role;
CREATE FUNCTION public.get_qr_bill_stock_v1(p_visit_id uuid,p_bill_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v zela_qr.visits; other_items jsonb;
BEGIN
 SELECT * INTO v FROM zela_qr.visits WHERE id=p_visit_id AND state='closing'
 AND bill_token=p_bill_token AND bill_actor=auth.uid();
 IF v.id IS NULL THEN RAISE EXCEPTION 'Tagihan QR tidak valid' USING ERRCODE='42501'; END IF;
 PERFORM public.v54_assert_branch(v.branch_id);
 SELECT coalesce(jsonb_agg(i),'[]') INTO other_items FROM zela_qr.batches b
 JOIN zela_qr.visits x ON x.id=b.visit_id CROSS JOIN LATERAL jsonb_array_elements(b.items)i
 WHERE x.branch_id=v.branch_id AND x.id<>v.id AND x.state IN ('open','closing') AND b.state='accepted';
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('stock_sisa',s.stock_sisa-coalesce(n.quantity,0))),'[]')
 FROM public.get_menu_stock_today_before_qr_v1(v.branch_id)s
 LEFT JOIN zela_qr.needs(v.branch_id,other_items)n ON n.name=s.menu_name_key);
END;
$$;
REVOKE ALL ON FUNCTION public.get_qr_bill_stock_v1(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_qr_bill_stock_v1(uuid,uuid) TO authenticated;
ALTER FUNCTION zela_sync.accept_food_receipt(jsonb) RENAME TO accept_food_receipt_before_qr_v1;
CREATE FUNCTION zela_sync.accept_food_receipt(p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r jsonb; branch uuid:=(p_payload->>'branch_id')::uuid; was_applied boolean;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('zela-food-sync:'||branch::text,0));
 SELECT EXISTS(SELECT 1 FROM zela_sync.food_receipts WHERE branch_id=branch AND order_number=p_payload->>'order_number' AND stock_applied) INTO was_applied;
 r:=zela_sync.accept_food_receipt_before_qr_v1(p_payload);
 IF NOT was_applied AND r->>'success'='true' AND r->>'stock_applied'='true' THEN PERFORM zela_qr.assert_reserved(branch); END IF;
 RETURN r;
END;
$$;
GRANT EXECUTE ON FUNCTION zela_sync.accept_food_receipt(jsonb) TO authenticated;
CREATE FUNCTION public.sync_qr_food_order_v1(p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v zela_qr.visits; expected jsonb; actual jsonb; r jsonb;
BEGIN
 SELECT * INTO v FROM zela_qr.visits WHERE id=(p_payload->>'qr_visit_id')::uuid FOR UPDATE;
 IF v.id IS NULL OR auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM v.bill_actor
 OR p_payload->>'account_id' IS DISTINCT FROM auth.uid()::text
 OR p_payload->>'branch_id' IS DISTINCT FROM v.branch_id::text
 OR p_payload->>'qr_bill_token' IS DISTINCT FROM v.bill_token::text
 OR p_payload->>'order_number' IS DISTINCT FROM v.receipt_number THEN
  RAISE EXCEPTION 'Sesi tagihan QR tidak sesuai' USING ERRCODE='42501'; END IF;
 PERFORM public.v54_assert_branch(v.branch_id);
 IF v.state='paid' THEN
  IF v.settlement->'payload' IS DISTINCT FROM p_payload THEN RAISE EXCEPTION 'Receipt QR berbeda' USING ERRCODE='22023'; END IF;
  RETURN v.settlement->'result';
 END IF;
 IF v.state<>'closing' THEN RAISE EXCEPTION 'Tagihan belum disiapkan' USING ERRCODE='P0001'; END IF;
 SELECT jsonb_agg(to_jsonb(q) ORDER BY q.name,q.price) INTO expected FROM(
  SELECT i->>'item_name' AS name,(i->>'price')::numeric AS price,sum((i->>'quantity')::numeric) AS qty
  FROM zela_qr.batches b CROSS JOIN LATERAL jsonb_array_elements(b.items)i WHERE b.visit_id=v.id AND b.state='accepted' GROUP BY 1,2)q;
 SELECT jsonb_agg(to_jsonb(q) ORDER BY q.name,q.price) INTO actual FROM(
  SELECT i->>'item_name' AS name,(i->>'price')::numeric AS price,sum((i->>'quantity')::numeric) AS qty
  FROM jsonb_array_elements(p_payload->'items')i GROUP BY 1,2)q;
 IF expected IS NULL OR expected IS DISTINCT FROM actual THEN RAISE EXCEPTION 'Isi tagihan QR berubah' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('zela-food-sync:'||v.branch_id::text,0));
 -- Remove this visit's reservation in the same transaction as financial/stock settlement.
 UPDATE zela_qr.visits SET state='paid',closed_at=now() WHERE id=v.id;
 IF p_payload ? 'member_number' THEN r:=public.zela_member_sync_food_order(p_payload);
 ELSE r:=public.sync_paid_food_order(p_payload); END IF;
 IF r->>'success' IS DISTINCT FROM 'true' OR r->>'stock_applied' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'Pembayaran QR belum dikonfirmasi' USING ERRCODE='P0001'; END IF;
 r:=r||jsonb_build_object('qr_billed',true,'qr_visit_id',v.id);
 UPDATE zela_qr.visits SET settlement=jsonb_build_object('payload',p_payload,'result',r) WHERE id=v.id;
 UPDATE public.restaurant_tables SET status='empty',customer_name=NULL,occupied_at=NULL WHERE id=v.table_id;
 RETURN r;
END;
$$;
REVOKE ALL ON ALL TABLES IN SCHEMA zela_qr FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA zela_qr FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.qr_guest_v1(text,jsonb),public.qr_staff_v1(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qr_guest_v1(text,jsonb),public.qr_staff_v1(uuid,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.sync_qr_food_order_v1(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.sync_qr_food_order_v1(jsonb) TO authenticated;
REVOKE ALL ON FUNCTION zela_sync.accept_food_receipt(jsonb) FROM PUBLIC,anon;
NOTIFY pgrst,'reload schema';
COMMIT;
