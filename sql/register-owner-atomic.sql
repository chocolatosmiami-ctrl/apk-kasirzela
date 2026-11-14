BEGIN;
CREATE OR REPLACE FUNCTION public.register_owner_business_atomic(
 p_auth_id uuid,p_email text,p_owner_name text,p_business_name text,p_phone text DEFAULT '')
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner_id uuid;
BEGIN
 IF p_auth_id IS NULL OR length(btrim(coalesce(p_owner_name,''))) NOT BETWEEN 1 AND 160
 OR length(btrim(coalesce(p_business_name,''))) NOT BETWEEN 1 AND 160
 OR length(coalesce(p_phone,''))>80
 OR coalesce(p_email,'') !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
 THEN RAISE EXCEPTION 'Invalid registration' USING ERRCODE='22023'; END IF;
 -- The server adapter creates the Auth identity first. This RPC is service-only;
 -- it requires no extra SQL access to Auth internals and grants clients nothing.
 INSERT INTO public.owners(auth_id,name,email,business_name,phone,is_active)
 VALUES(p_auth_id,p_owner_name,lower(p_email),p_business_name,coalesce(p_phone,''),true) RETURNING id INTO owner_id;
 -- Preserve the existing registration trial values; a failure rolls back both inserts.
 INSERT INTO public.subscriptions(owner_id,balance,is_trial,is_locked,cost_per_trx,total_transactions)
 VALUES(owner_id,5000,true,false,500,0);
 RETURN owner_id;
END $$;
REVOKE ALL ON FUNCTION public.register_owner_business_atomic(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_owner_business_atomic(uuid,text,text,text,text) TO service_role;
COMMIT;
