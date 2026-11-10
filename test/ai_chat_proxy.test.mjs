import { handleAiChat } from '../supabase/functions/ai-chat/handler.mjs';
import assert from 'node:assert/strict';
const valid={context:'Data dummy',messages:[{role:'user',content:'Bantu analisis'}]};
const request=(body=valid,authorization='Bearer test-token')=>new Request('https://local.invalid',{
 method:'POST',headers:{authorization},body:JSON.stringify(body)});
let calls=0;
const deps={authenticate:async()=>({id:'dummy'}),configured:()=>true,
 reserve:async()=>({allowed:true,status:200}),complete:async()=>{calls++;return 'Jawaban';}};
assert.equal((await handleAiChat(request(valid,''),deps)).status,401);
assert.equal((await handleAiChat(request(),{...deps,authenticate:async()=>null})).status,401);
assert.equal((await handleAiChat(request(),{...deps,configured:()=>false})).status,503);
assert.equal((await handleAiChat(request(),{...deps,reserve:async()=>({allowed:false,status:403})})).status,403);
assert.equal((await handleAiChat(request(),{...deps,reserve:async()=>({allowed:false,status:429})})).status,429);
assert.equal((await handleAiChat(request({context:'',messages:[{role:'system',content:'escape'}]}),deps)).status,400);
assert.equal((await handleAiChat(request({...valid,context:'x'.repeat(70000)}),deps)).status,413);
assert.equal(calls,0);
const ok=await handleAiChat(request(),deps);
assert.equal(ok.status,200); assert.deepEqual(await ok.json(),{reply:'Jawaban'});
const error=await handleAiChat(request(),{...deps,complete:async()=>{throw new Error('PRIVATE_SECRET');}});
assert.equal(error.status,503); assert.ok(!(await error.text()).includes('PRIVATE_SECRET'));
console.log('PASS AI auth, role/quota denial, payload bounds, model-role injection rejection, success, sanitized error');
