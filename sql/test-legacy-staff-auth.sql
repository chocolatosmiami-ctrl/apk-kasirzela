-- Execute within an outer BEGIN/ROLLBACK. Does not create or reset Auth accounts.
do $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := 'fixture-'||gen_random_uuid()||'@example.invalid';
  v_result jsonb;
  i integer;
begin
  insert into public.users(id,name,email,role,password,is_active,is_approved)
    values(v_id,'ROLLBACK legacy login fixture',v_email,'kasir',
      encode(extensions.digest('Synthetic-test-password-938!','sha256'),'hex'),true,true);
  execute 'set local role service_role';
  for i in 1..5 loop
    v_result := public.prepare_legacy_staff_login(v_email);
    if v_result->>'status' <> 'ok' then raise exception 'Valid legacy profile not available'; end if;
  end loop;
  v_result := public.prepare_legacy_staff_login(v_email);
  if v_result->>'status' <> 'limited' then raise exception 'Rate limit not enforced'; end if;
  if public.link_legacy_staff_auth(v_id,null) then raise exception 'Null Auth identity accepted'; end if;
  execute 'reset role';
  update zela_sync.staff_login_attempts set window_started=now()-interval '16 minutes';
  execute 'set local role service_role';
  v_result := public.prepare_legacy_staff_login(v_email);
  if v_result->>'status' <> 'ok' then raise exception 'Expired limit did not reset'; end if;
  execute 'reset role';
  update public.users set is_active=false where id=v_id;
  execute 'set local role service_role';
  v_result := public.prepare_legacy_staff_login(v_email);
  if v_result->>'status' <> 'invalid' then raise exception 'Inactive staff accepted'; end if;
  execute 'reset role';
  if has_function_privilege('anon','public.prepare_legacy_staff_login(text)','execute')
     or has_function_privilege('authenticated','public.prepare_legacy_staff_login(text)','execute')
     or has_function_privilege('anon','public.link_legacy_staff_auth(uuid,uuid)','execute')
     or has_function_privilege('authenticated','public.link_legacy_staff_auth(uuid,uuid)','execute') then
    raise exception 'Client can access migration helpers';
  end if;
  if not has_table_privilege('service_role','public.users','UPDATE') then
    raise exception 'Service cannot link real staff profile';
  end if;
end;
$$;
