import {readBoundedText} from '../_shared/bounded_body.mjs';
const headers={'Content-Type':'application/json','Cache-Control':'no-store',
 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info',
 'Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers});
export async function registerOwner(request,services) {
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='POST')return reply(405,{error:'METHOD_NOT_ALLOWED'});
 let body;
 try{body=JSON.parse(await readBoundedText(request,16384));}catch{return reply(400,{error:'INVALID_REQUEST'});}
 if(!body||typeof body.email!=='string'||! /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(body.email.trim())||body.email.length>254||
 typeof body.password!=='string'||body.password.length<6||body.password.length>128||
 ['name','owner_name','business_name'].some(k=>typeof body[k]!=='string'||!body[k].trim()||body[k].length>160)||
 (body.phone!==undefined&&(typeof body.phone!=='string'||body.phone.length>80)))return reply(400,{error:'INVALID_REQUEST'});
 let userId;
 try {
  userId=await services.createAuth({...body,email:body.email.trim().toLowerCase()});
  if(!userId)return reply(400,{error:'ACCOUNT_NOT_CREATED'});
  // This service-only database RPC commits owner and subscription together.
  const ownerId=await services.createBusiness(userId,{...body,email:body.email.trim().toLowerCase()});
  if(!ownerId)throw new Error('BUSINESS_NOT_CREATED');
  return reply(200,{success:true,owner_id:ownerId,user_id:userId});
 }catch(error) {
  // A timeout may hide a committed RPC. Delete Auth only after a definite DB rollback.
  if(userId&&error?.businessRolledBack===true){try{await services.removeAuth(userId);}catch{/* Requires reconciliation; never report success. */}}
  return reply(503,{error:'REGISTRATION_UNAVAILABLE'});
 }
}
