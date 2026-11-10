// Actual PostgreSQL (PGlite), isolated synthetic data; never connects to Supabase.
// npm ci && npm test
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const root = new URL('../', import.meta.url);
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const roles = ['postgres','ownerA','cashierA','ownerB','cashierB','adminA','managerA','sa','disabled'];
const uid = Object.fromEntries(roles.map((r,i)=>[r,id(i+100)]));
const ownerA=id(1),ownerB=id(2),branchA=id(11),branchB=id(12),branchA2=id(13);
await db.exec(`
 create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; create schema extensions;
 create function auth.uid() returns uuid language sql stable as
 $$ select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;
 create function auth.role() returns text language sql stable as
 $$ select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','') $$;
 grant usage on schema auth to public; grant execute on all functions in schema auth to public;
 create table owners(id uuid primary key,auth_id uuid,name text,email text,is_active boolean default true);
 create table branches(id uuid primary key,owner_id uuid,name text,is_active boolean default true);
 create table users(id uuid primary key default gen_random_uuid(),auth_id uuid,owner_id uuid,branch_id uuid,
   name text,email text,role text,is_active boolean default true,is_approved boolean default true,
   pin_hash text,password text,wa_number text,created_at timestamptz default now());
 create table orders(id bigserial primary key,order_number text,cashier_id uuid,cashier_name text,
   branch_id uuid,order_type text,status text,subtotal numeric,discount numeric,tax numeric,total numeric,
   payment_method text,paid_amount numeric,change_amount numeric,notes text,created_at timestamptz,daily_seq int);
 create table order_items(id bigserial primary key,order_id bigint,item_name text,quantity numeric,
   unit text,price numeric,subtotal numeric);
 create table subscriptions(owner_id uuid,balance numeric);
 create table menu_stock(branch_id uuid,name text);
 create table menu_items(id bigint,name text,branch_id uuid,price numeric,is_available boolean);
 create table restaurant_tables(id bigint,name text,branch_id uuid,zone text,capacity int,status text);
 create table deductions(n int); insert into deductions values(0);
 create function public.assert_stock_available(uuid,json) returns void language sql as $$ select $$;
 create function public.deduct_transaction(uuid) returns void language sql as $$ update deductions set n=n+1 $$;
 create function public.setup_superadmin(text,text) returns json language sql as $$ select '{}'::json $$;
 create function public.setup_superadmin(uuid,text) returns json language sql as $$ select '{}'::json $$;
 create function public.query(query text) returns json language sql security definer as $$ select '{}'::json $$;
 grant all on all tables in schema public to authenticated,anon,service_role;
 grant usage,select on all sequences in schema public to authenticated,anon,service_role;
 alter table users enable row level security; alter table orders enable row level security;
 alter table subscriptions enable row level security; alter table menu_stock enable row level security;
 alter table owners enable row level security;
 create policy users_legacy on users for all using(true) with check(true);
 create policy orders_read_policy on orders for select using(true);
 create policy orders_legacy on orders for all using(true) with check(true);
 create policy subscriptions_legacy on subscriptions for all using(true) with check(true);
 create policy menu_legacy on menu_stock for all using(true) with check(true);
 create policy owners_legacy on owners for all using(true) with check(true);
`);
for (const [owner,account] of [[ownerA,'ownerA'],[ownerB,'ownerB']]) {
  await db.query('insert into owners values($1,$2,$3,$4,true)',[owner,uid[account],account,`${account}@example.invalid`]);
}
for (const [branch,owner] of [[branchA,ownerA],[branchA2,ownerA],[branchB,ownerB]]) {
  await db.query('insert into branches values($1,$2,$3,true)',[branch,owner,branch]);
}
for (const [account,role,owner,branch] of [
 ['ownerA','owner',ownerA,null],['ownerB','owner',ownerB,null],
 ['cashierA','kasir',ownerA,branchA],['cashierB','kasir',ownerB,branchB],
 ['adminA','admin',ownerA,branchA],['managerA','manajer',ownerA,branchA],
 ['sa','superadmin',ownerA,null],['disabled','kasir',ownerA,branchA]]) {
 await db.query(`insert into users(auth_id,owner_id,branch_id,name,email,role,is_active)
   values($1,$2,$3,$4,$5,$6,$7)`,[uid[account],owner,branch,account,`${account}@example.invalid`,role,account!=='disabled']);
}
await db.query("insert into orders(order_number,branch_id,status,total) values('A',$1,'paid',10),('B',$2,'completed',20)",[branchA,branchB]);
await db.query('insert into subscriptions values($1,100),($2,200)',[ownerA,ownerB]);
for (const path of ['sql/security-hardening.sql','sql/security-legacy-orders.sql','sql/security-ai-quota.sql']) {
 await db.exec(readFileSync(new URL(path,root),'utf8'));
}
async function as(account,role='authenticated') {
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role,...(uid[account]?{sub:uid[account]}:{})})]);
 await db.exec(`set role ${role}`);
}
async function denied(sql,args=[]) {
 await assert.rejects(db.query(sql,args));
}
await as(null,'anon');
for (const table of ['users','owners','orders','subscriptions','menu_stock']) {
 await denied(`select * from ${table}`);
}
await denied("select table_search('orders','',10)");
await denied("select setup_superadmin($1::uuid,'bad@example.invalid')",[uid.cashierA]);
console.log('PASS anonymous reads, generic search and superadmin provisioning denied');
await as('cashierA');
await denied("select public.query('select 1')");
assert.equal((await db.query('select order_number from orders')).rows[0].order_number,'A');
assert.equal((await db.query('select * from orders')).rows.length,1);
assert.equal((await db.query('select * from subscriptions')).rows.length,1);
await denied("update users set role='superadmin' where auth_id=$1",[uid.cashierA]);
await denied('update users set owner_id=$1 where auth_id=$2',[ownerB,uid.cashierA]);
await denied('update users set is_approved=false where auth_id=$1',[uid.cashierA]);
await db.query("update users set name='New name',pin_hash='test-hash' where auth_id=$1",[uid.cashierA]);
assert.equal((await db.query('update subscriptions set balance=999 returning *')).rows.length,0);
await denied("insert into subscriptions values($1,999)",[ownerA]);
await denied("select table_search('users','',10)");
console.log('PASS cashier tenant isolation, own PIN/name allowed, role/tenancy/approval/balance tampering denied');
await as('ownerA');
await db.query("update users set role='manajer' where auth_id=$1",[uid.cashierA]);
await db.query("update users set role='kasir' where auth_id=$1",[uid.cashierA]);
await denied("update users set role='superadmin' where auth_id=$1",[uid.cashierA]);
await denied("select table_search('users','',101)");
await denied("select table_search('subscriptions','',10)");
assert.equal((await db.query("select table_search('orders','',10) as found")).rows[0].found.length,1);
console.log('PASS owner staff management retained, sensitive-table search and excessive limit denied');
await as('disabled');
assert.equal((await db.query('select * from orders')).rows.length,0);
await as('sa');
assert.equal((await db.query('select * from orders')).rows.length,2);
assert.equal((await db.query('update subscriptions set balance=balance+1 returning *')).rows.length,2);
console.log('PASS inactive account denied and provisioned superadmin access retained');

const call = `select insert_order(p_branch_id=>$1::uuid,p_cashier_id=>'spoof',p_cashier_name=>'spoof',
 p_order_number=>$2,p_order_type=>'retail',p_status=>'paid',p_subtotal=>10,p_total=>10,
 p_paid_amount=>10,p_items=>'[{"item_name":"Item","quantity":1,"price":10,"subtotal":10}]'::json) as result`;
await as('cashierA');
const first=(await db.query(call,[branchA,'RT-stable'])).rows[0].result;
assert.equal(first.success,true);
const retry=(await db.query(call,[branchA,'RT-stable'])).rows[0].result;
assert.deepEqual(first,retry);
assert.equal((await db.query("select cashier_name from orders where order_number='RT-stable'")).rows[0].cashier_name,'New name');
await denied(call,[branchB,'RT-cross']);
await denied(call,[branchA2,'RT-cross-branch']);
await denied(call.replace('p_total=>10','p_total=>11'),[branchA,'RT-stable']);
await denied(call,[branchA,'']);
await as('ownerA');
await denied(call,[branchA,'RT-stable']); // Different actor cannot claim receipt.
await as(null,'anon'); await denied(call,[branchA,'RT-anon']);
await as(null,'service_role');
const d=(await db.query('select n from deductions')).rows[0].n;
assert.equal(d,1);
console.log('PASS real legacy SQL adapter: canonical cashier, stable retry, one deduction, conflict/cross-tenant/anon denied');
await as('ownerA');
await denied('select public.reserve_ai_chat($1::uuid)',[uid.ownerA]);
await as(null,'service_role');
assert.equal((await db.query('select public.reserve_ai_chat($1::uuid) as q',[uid.cashierA])).rows[0].q.status,403);
for (let i=0;i<10;i++) {
 assert.equal((await db.query('select public.reserve_ai_chat($1::uuid) as q',[uid.ownerA])).rows[0].q.allowed,true);
}
assert.equal((await db.query('select public.reserve_ai_chat($1::uuid) as q',[uid.ownerA])).rows[0].q.status,429);
assert.equal((await db.query('select public.reserve_ai_chat($1::uuid) as q',[uid.ownerB])).rows[0].q.allowed,true);
console.log('PASS AI quota service-only, cashier denied, owner quota enforced and separate owners isolated');
await db.close();
