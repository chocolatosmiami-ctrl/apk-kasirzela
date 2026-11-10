export function staffServices() {
 const url=Deno.env.get('SUPABASE_URL')??'';
 const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
 const headers={apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'};
 async function call(path: string,method='GET',body?: unknown,extra={}) {
   const r=await fetch(url+path,{method,headers:{...headers,...extra},
     ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});
   if(!r.ok) throw new Error('SERVICE_UNAVAILABLE');
   return await r.json();
 }
 return {serviceKey,
   async staff(id: string) {
     const rows=await call('/rest/v1/users?id=eq.'+encodeURIComponent(id)+'&select=id,email,auth_id,role,is_active,is_approved');
     return rows[0];
   },
   async createAuth(email: string,password: string) {
     return (await call('/auth/v1/admin/users','POST',{email,password,email_confirm:true})).id;
   },
   async resetAuth(id: string,password: string) {await call('/auth/v1/admin/users/'+encodeURIComponent(id),'PUT',{password});},
   async saveProfile(id: string,previous: string|null,authId: string,hash: string) {
     const rows=await call('/rest/v1/users?id=eq.'+encodeURIComponent(id)+'&auth_id='+(previous?'eq.'+encodeURIComponent(previous):'is.null'),
       'PATCH',{auth_id:authId,password:hash},{Prefer:'return=representation'});
     return rows.length===1;
   },
 };
}
