import {readBoundedText} from './bounded_body.mjs';
const response=(status,body)=>new Response(JSON.stringify(body),{status,
  headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
function equal(a,b) {
 if(a.length!==b.length) return false;
 let diff=0; for(let i=0;i<a.length;i++) diff|=a.charCodeAt(i)^b.charCodeAt(i);
 return diff===0;
}
export async function staffMaintenance(request,services,operation) {
 if(request.method!=='POST') return response(405,{error:'METHOD_NOT_ALLOWED'});
 const authorization=request.headers.get('authorization')??'';
 if(!services.serviceKey || !equal(authorization,'Bearer '+services.serviceKey)) {
   return response(401,{error:'SERVER_CREDENTIAL_REQUIRED'});
 }
 let body;
 try {body=JSON.parse(await readBoundedText(request,4096));}
 catch {return response(400,{error:'INVALID_REQUEST'});}
 if(body?.confirm!==true || !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(body.staff_id??'') ||
    typeof body.new_password!=='string' || body.new_password.length<12 || body.new_password.length>128) {
   return response(400,{error:'TARGET_AND_STRONG_PASSWORD_REQUIRED'});
 }
 try {
   const staff=await services.staff(body.staff_id);
   if(!staff) return response(404,{error:'STAFF_NOT_FOUND'});
   if(!staff.is_active || !staff.is_approved || !['kasir','manajer','admin'].includes(staff.role)) {
     return response(403,{error:'STAFF_NOT_ELIGIBLE'});
   }
   let authId=staff.auth_id;
   if(operation==='provision') {
     if(authId) return response(409,{error:'ALREADY_PROVISIONED'});
     authId=await services.createAuth(staff.email,body.new_password);
   } else {
     if(!authId) return response(409,{error:'PROVISION_AUTH_FIRST'});
     await services.resetAuth(authId,body.new_password);
   }
   if(!authId) return response(409,{error:'AUTH_ACCOUNT_REQUIRES_REVIEW'});
   const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',
     new TextEncoder().encode(body.new_password))),b=>b.toString(16).padStart(2,'0')).join('');
   if(!await services.saveProfile(staff.id,staff.auth_id,authId,hash)) {
     return response(409,{error:'AUTH_PROFILE_REQUIRES_RECONCILIATION'});
   }
   return response(200,{success:true,staff_id:staff.id});
 } catch {return response(503,{error:'MAINTENANCE_UNAVAILABLE'});}
}
