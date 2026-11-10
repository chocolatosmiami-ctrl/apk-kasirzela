import {staffMaintenance} from '../supabase/functions/_shared/staff_maintenance.mjs';
import assert from 'node:assert/strict';
const target='00000000-0000-4000-8000-000000000001';
const payload={confirm:true,staff_id:target,new_password:'dummy-password-123'};
const request=(body=payload,key='server-test')=>new Request('https://local.invalid',{
 method:'POST',headers:{authorization:'Bearer '+key},body:JSON.stringify(body)});
let creates=0,resets=0,saved;
const services={serviceKey:'server-test',staff:async()=>({id:target,email:'dummy@example.invalid',
 is_active:true,is_approved:true,role:'kasir',auth_id:null}),
 createAuth:async()=>{creates++;return target;},resetAuth:async()=>{resets++;},
 saveProfile:async(...args)=>{saved=args;return true;}};
assert.equal((await staffMaintenance(request(payload,'ordinary-user-jwt'),services,'provision')).status,401);
assert.equal((await staffMaintenance(request({...payload,new_password:'short'}),services,'provision')).status,400);
assert.equal((await staffMaintenance(request(),services,'repair')).status,409);
assert.equal(creates+resets,0);
assert.equal((await staffMaintenance(request(),services,'provision')).status,200);
assert.equal(creates,1);assert.equal(saved[3].length,64);assert.notEqual(saved[3],payload.new_password);
assert.equal((await staffMaintenance(request(),{...services,staff:async()=>({id:target,auth_id:target,
 is_active:true,is_approved:true,role:'kasir'})},'repair')).status,200);
assert.equal(resets,1);
console.log('PASS maintenance: server-only, explicit target/confirmation, strong password, no batch/default credentials, provision/repair preserved');
