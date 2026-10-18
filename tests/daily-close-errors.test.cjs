const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function client(message,code='P0001'){
 const calls=[],owner='3abeebcc-c8ad-43c3-8f7d-b40bd4c0e47b',session={access_token:'fixture-access',refresh_token:'fixture-refresh',expires_at:9999999999,user:{id:owner}},stored=JSON.stringify(session),context={
  KashierConfig:{url:'https://fixture.invalid',publishableKey:'fixture-key'},sessionStorage:{getItem:()=>stored},Date,JSON,Number,BigInt,String,Error,URLSearchParams,AbortSignal:{timeout:()=>null},
  fetch:async(url,options)=>{calls.push({url,options});return {ok:false,status:400,text:async()=>JSON.stringify({message,code})};}
 };context.globalThis=context;vm.runInNewContext(fs.readFileSync(require.resolve('../data.js'),'utf8'),context);return {api:context.KashierData,calls};
}
const cases={close_auth_required:/بچۆ ژوورەوە/,close_invalid_range:/٣١ ڕۆژ/,close_completed_day_required:/کاتی بەغدا/,close_invalid_request:/بڕ و هۆکار/,close_snapshot_changed:/نوێ بکەرەوە/,close_difference_reason_required:/هۆکاری/,close_day_already_closed:/پێشتر داخراوە/,close_request_conflict:/بەڵگەی داخستن بپشکنە/};
for(const endpoint of ['preview','history','post'])test('daily close '+endpoint+' localizes server failures while preserving retry classification and one request',async()=>{
 for(const [code,expected] of Object.entries(cases)){
  const {api,calls}=client(code),invoke=()=>endpoint==='preview'?api.getDailyClosePreview('2026-05-04'):endpoint==='history'?api.getDailyCloseHistory('2026-05-01','2026-05-04'):api.postDailyClose('a103a461-04f5-47cf-bced-f7eb0316d26f','2026-05-04','15000','counted','a'.repeat(64));
  await assert.rejects(invoke,e=>{assert.match(e.message,expected);assert.equal(e.saleCode,code);assert.equal(e.code,'P0001');assert.equal(e.status,400);return true;});
  assert.equal(calls.length,1);assert.equal(calls[0].options.method,'POST');assert.equal(calls[0].options.headers.Authorization,'Bearer fixture-access');
  const body=JSON.parse(calls[0].options.body);assert.equal('owner_id' in body,false);
  if(endpoint==='post'){assert.equal(body.p_actual,'15000');assert.equal(body.p_ack,true);}
 }
 const {api}=client('unrecognized_internal_detail');await assert.rejects(()=>api.getDailyClosePreview('2026-05-04'),e=>{assert.doesNotMatch(e.message,/unrecognized_internal_detail/);assert.equal(e.saleCode,'unrecognized_internal_detail');return true;});
});
