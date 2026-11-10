import {readBoundedText} from '../_shared/bounded_body.mjs';
const headers={'Content-Type':'application/json','Cache-Control':'no-store'};
const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers});
export async function verifyMidtransSignature(body,key) {
  if (!key || typeof body.signature_key!=='string' || !/^[a-f0-9]{128}$/i.test(body.signature_key)) return false;
  const bytes=new TextEncoder().encode(body.order_id+body.status_code+body.gross_amount+key);
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-512',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
  let difference=0; const actual=body.signature_key.toLowerCase();
  for(let i=0;i<hash.length;i++) difference|=hash.charCodeAt(i)^actual.charCodeAt(i);
  return difference===0;
}
export async function handleMidtrans(request,services) {
  if (request.method!=='POST') return reply(405,{error:'METHOD_NOT_ALLOWED'});
  if (!services.serverKey) return reply(503,{error:'PAYMENT_NOT_CONFIGURED'});
  let body;
  try {
    const text=await readBoundedText(request,32768);
    body=JSON.parse(text);
  } catch { return reply(400,{error:'INVALID_PAYLOAD'}); }
  if (!body || typeof body.order_id!=='string' || body.order_id.length<1 || body.order_id.length>160 ||
      typeof body.status_code!=='string' || !/^\d{3}$/.test(body.status_code) ||
      typeof body.gross_amount!=='string' || !/^\d+(\.\d{1,2})?$/.test(body.gross_amount) ||
      !Number.isFinite(Number(body.gross_amount)) || Number(body.gross_amount)<=0 ||
      typeof body.transaction_status!=='string') return reply(400,{error:'INVALID_PAYLOAD'});
  if (!await verifyMidtransSignature(body,services.serverKey)) return reply(403,{error:'INVALID_SIGNATURE'});
  try {
    const result=await services.process(body);
    if (!result || (result.success!==true && !['cancel','deny','expire'].includes(result.error))) {
      // Return failure so the provider can retry; never claim receipt before DB confirmation.
      return reply(503,{error:'PAYMENT_PROCESSING_UNAVAILABLE'});
    }
    return reply(200,{received:true});
  } catch { return reply(503,{error:'PAYMENT_PROCESSING_UNAVAILABLE'}); }
}
