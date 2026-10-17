const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

function setup(response){
 const calls=[];
 const memory={'kashier.auth.v1':JSON.stringify({access_token:'fresh-token'})};
 const context={
  KashierConfig:{url:'https://example.invalid',publishableKey:'sb_publishable_test'},
  KashierData:{loggedIn:()=>true,getAccount:async()=>({id:'owner'})},
  sessionStorage:{getItem:key=>memory[key]||null,setItem:(key,value)=>memory[key]=value,removeItem:key=>delete memory[key]},
  AbortSignal,
  fetch:async(url,options)=>{calls.push({url,options});return {ok:response.status<400,status:response.status,text:async()=>JSON.stringify(response.data)};}
 };
 vm.runInNewContext(fs.readFileSync(require.resolve('../returns-data.js'),'utf8'),context);
 return {api:context.KashierReturns,calls};
}

test('returns report client refreshes account and posts server filters with the user token',async()=>{
 const x=setup({status:200,data:{count:'2',rows:[{kind:'partial'},{kind:'full'}]}});
 const result=await x.api.list({kind:'partial',from:'2026-10-01',to:'2026-10-17',query:'12',page:2,limit:50});
 assert.equal(result.total,2);assert.equal(result.rows.length,2);
 assert.match(x.calls[0].url,/\/rpc\/get_sale_returns_report$/);
 assert.equal(x.calls[0].options.headers.Authorization,'Bearer fresh-token');
 assert.equal(x.calls[0].options.headers.apikey,'sb_publishable_test');
 assert.deepEqual(JSON.parse(x.calls[0].options.body),{p_kind:'partial',p_from:'2026-10-01',p_to:'2026-10-17',p_query:'12',p_offset:100,p_limit:50});
});

test('returns report client maps backend validation codes to Kurdish',async()=>{
 const x=setup({status:400,data:{message:'returns_invalid_dates',code:'P0001'}});
 await assert.rejects(x.api.list({from:'2026-10-17',to:'2026-10-01'}),error=>error.code==='returns_invalid_dates'&&error.message.includes('بەرواری سەرەتا'));
});

test('returns report client rejects malformed report payloads',async()=>{
 const x=setup({status:200,data:{count:'x',rows:[]}});
 await assert.rejects(x.api.list(),/وەڵامی ڕاپۆرت گونجاو نییە/);
});
