import {registerOwner} from './handler.mjs';
const url=Deno.env.get('SUPABASE_URL')??'';
const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
async function call(path:string,method:string,body?:unknown){
 if(!url||!key)throw new Error('NOT_CONFIGURED');
 const response=await fetch(url+path,{method,headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},
  ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(15000)});
 if(!response.ok){
  const failure=await response.json().catch(()=>({}));
  throw Object.assign(new Error('BACKEND_UNAVAILABLE'),{businessRolledBack:
   path==='/rest/v1/rpc/register_owner_business_atomic'&&/^(?:[234][A-Z0-9]{4}|P0001)$/.test(failure.code??'')});
 }
 return await response.json();
}
Deno.serve((request:Request)=>registerOwner(request,{
 async createAuth(body:Record<string,string>){return (await call('/auth/v1/admin/users','POST',{
  email:body.email,password:body.password,email_confirm:true,user_metadata:{full_name:body.name}})).id;},
 async createBusiness(userId:string,body:Record<string,string>){return await call('/rest/v1/rpc/register_owner_business_atomic','POST',{
  p_auth_id:userId,p_email:body.email,p_owner_name:body.owner_name,p_business_name:body.business_name,p_phone:body.phone??''});},
 async removeAuth(userId:string){await call('/auth/v1/admin/users/'+encodeURIComponent(userId),'DELETE');},
}));
