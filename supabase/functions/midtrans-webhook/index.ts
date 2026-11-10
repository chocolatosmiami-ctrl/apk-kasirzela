import { handleMidtrans } from './handler.mjs';
const url=Deno.env.get('SUPABASE_URL')??'';
const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
Deno.serve((request: Request)=>handleMidtrans(request,{
  serverKey:Deno.env.get('MIDTRANS_SERVER_KEY')??'',
  async process(body: Record<string,string>) {
    const r=await fetch(url+'/rest/v1/rpc/process_midtrans_topup_webhook',{
      method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},
      body:JSON.stringify({p_midtrans_order_id:body.order_id,p_transaction_status:body.transaction_status,
        p_fraud_status:body.fraud_status??'',p_gross_amount:Number(body.gross_amount),
        p_payment_type:body.payment_type??'',p_raw_payload:body}),signal:AbortSignal.timeout(10000),
    });
    if(!r.ok) throw new Error('DATABASE_UNAVAILABLE');
    return await r.json();
  },
}));
