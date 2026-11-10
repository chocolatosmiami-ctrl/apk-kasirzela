import { handleAiChat } from './handler.mjs';
const url=Deno.env.get('SUPABASE_URL')??'';
const anon=Deno.env.get('SUPABASE_ANON_KEY')??'';
const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
// Provider credential is configured as a Supabase secret, never in Dart/source.
const aiKey=Deno.env.get('ZELA_AI_API_KEY')??'';
Deno.serve((request: Request)=>handleAiChat(request,{
  configured:()=>Boolean(aiKey),
  async authenticate(authorization: string) {
    const r=await fetch(url+'/auth/v1/user',{headers:{apikey:anon,Authorization:authorization},signal:AbortSignal.timeout(5000)});
    if (r.status===401 || r.status===403) return null;
    if (!r.ok) throw new Error('AUTH_UNAVAILABLE');
    return await r.json();
  },
  async reserve(id: string) {
    const r=await fetch(url+'/rest/v1/rpc/reserve_ai_chat',{
      method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},
      body:JSON.stringify({p_auth_id:id}),signal:AbortSignal.timeout(5000),
    });
    if (!r.ok) throw new Error('QUOTA_UNAVAILABLE');
    return await r.json();
  },
  async complete(messages: unknown[]) {
    const r=await fetch('https://api.cometapi.com/v1/chat/completions',{
      method:'POST',headers:{Authorization:'Bearer '+aiKey,'Content-Type':'application/json'},
      body:JSON.stringify({model:'gpt-4.1-mini',messages,max_tokens:1000,temperature:0.7,stream:false}),
      signal:AbortSignal.timeout(20000),
    });
    if (!r.ok) throw new Error('UPSTREAM');
    const body=await r.json(); return body.choices?.[0]?.message?.content;
  },
}));
