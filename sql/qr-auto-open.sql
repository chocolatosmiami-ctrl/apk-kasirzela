-- Automatic visit on guest join; existing payments close visits. No business data rewritten.
BEGIN;
SET LOCAL lock_timeout='3s';
CREATE OR REPLACE FUNCTION public.qr_guest_v1(p_action text,p_data jsonb) RETURNS jsonb
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
  RETURN jsonb_build_object('branch',t.branch_name,'table',t.name,'visit_id',v.id,'state',coalesce(v.state,'ready'),
   'menu',zela_qr.catalog(t.branch_id,v.id IS NULL OR v.state='open'),
   'fees',jsonb_build_object('tax_enabled',t.ppn_enabled,'tax_percent',t.ppn_persen,'service_enabled',t.sc_enabled,'service_amount',t.sc_amount,'rounding',t.rounding));
 END IF;
 -- Creating a visit is a write: only join immediately before submission may do it.
 -- Serialize on the same table row as staff open; concurrent guests share one visit.
 IF p_action='join' AND v.id IS NULL THEN
  PERFORM 1 FROM public.restaurant_tables WHERE id=t.id FOR UPDATE;
  SELECT * INTO v FROM zela_qr.visits WHERE table_id=t.id AND state IN ('open','closing');
  IF v.id IS NULL THEN
   IF (SELECT status FROM public.restaurant_tables WHERE id=t.id)<>'empty'
    OR EXISTS(SELECT 1 FROM public.table_carts WHERE branch_id=t.branch_id AND table_id=t.id) THEN
    RAISE EXCEPTION 'Meja masih memiliki pesanan kasir. Hubungi kasir.' USING ERRCODE='P0001'; END IF;
   INSERT INTO zela_qr.visits(table_id,branch_id) VALUES(t.id,t.branch_id) RETURNING * INTO v;
   UPDATE public.restaurant_tables SET status='occupied',occupied_at=now(),customer_name='Pesanan QR' WHERE id=t.id;
  END IF;
 END IF;
 IF v.id IS NULL THEN RAISE EXCEPTION 'Sesi meja belum tersedia. Kirim pesanan kembali.' USING ERRCODE='P0001'; END IF;
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


COMMIT;
