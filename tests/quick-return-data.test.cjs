const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

function setup(response,{loggedIn=true}={}){
 const calls=[],memory={'kashier.auth.v1':JSON.stringify({access_token:'fresh-token'})};
 let accountCalls=0;
 const context={
  KashierConfig:{url:'https://example.invalid',publishableKey:'sb_publishable_test'},
  KashierData:{loggedIn:()=>loggedIn,getAccount:async()=>{accountCalls++;return {id:'owner'};}},
  sessionStorage:{getItem:key=>memory[key]||null,setItem:(key,value)=>memory[key]=value,removeItem:key=>delete memory[key]},
  AbortSignal,URLSearchParams,
  fetch:async(url,options)=>{calls.push({url,options});return {ok:response.status<400,status:response.status,text:async()=>JSON.stringify(response.data)};}
 };
 vm.runInNewContext(fs.readFileSync(require.resolve('../return-lookup-data.js'),'utf8'),context);
 return {api:context.KashierReturnLookup,calls,get accountCalls(){return accountCalls;}};
}

const sale={id:'11111111-1111-4111-8111-111111111111',receipt_no:123,created_at:'2026-10-17T12:00:00Z',customer_name:'کڕیار',total:12500,payment_mode:'cash',debt_amount:0,discount:0};

test('receipt scanner normalizes digits and K-prefixed CODE128 values without Number precision loss',()=>{
 const x=setup({status:200,data:[]});
 assert.equal(x.api.normalize('123'),'123');
 assert.equal(x.api.normalize('K-00123'),'123');
 assert.equal(x.api.normalize(' k123 '),'123');
 assert.equal(x.api.normalize('K-9223372036854775807'),'9223372036854775807');
 assert.throws(()=>x.api.normalize('P-123'),/ژمارەی پسوولە/);
 assert.throws(()=>x.api.normalize('K-9223372036854775808'),/سنووری/);
});

test('quick return lookup uses authenticated exact receipt number filter and no broad search',async()=>{
 const x=setup({status:200,data:[sale]});
 const row=await x.api.find('K-123');
 assert.equal(row.id,sale.id);assert.equal(x.accountCalls,1);assert.equal(x.calls.length,1);
 const url=new URL(x.calls[0].url);
 assert.equal(url.pathname,'/rest/v1/sales');
 assert.equal(url.searchParams.get('receipt_no'),'eq.123');
 assert.equal(url.searchParams.get('limit'),'2');
 assert.match(url.searchParams.get('select'),/payment_mode/);
 assert.equal(x.calls[0].options.headers.Authorization,'Bearer fresh-token');
 assert.equal(x.calls[0].options.headers.apikey,'sb_publishable_test');
 assert.equal(url.searchParams.has('or'),false);
});

test('invalid scan is rejected before authentication or network access',async()=>{
 const x=setup({status:200,data:[sale]});
 await assert.rejects(x.api.find('customer name'),/ژمارەی پسوولە/);
 assert.equal(x.accountCalls,0);assert.equal(x.calls.length,0);
});

test('missing receipt returns null while duplicate or malformed server rows are rejected',async()=>{
 const missing=setup({status:200,data:[]});assert.equal(await missing.api.find('K-9'),null);
 const duplicate=setup({status:200,data:[sale,sale]});await assert.rejects(duplicate.api.find('123'),/وەڵامی پسوولە گونجاو نییە/);
 const malformed=setup({status:200,data:[{...sale,id:'bad'}]});await assert.rejects(malformed.api.find('123'),/زانیاری پسوولە گونجاو نییە/);
});

test('quick return lookup requires a signed-in session',async()=>{
 const x=setup({status:200,data:[sale]},{loggedIn:false});
 await assert.rejects(x.api.find('123'),/سەرەتا بچۆ ژوورەوە/);assert.equal(x.calls.length,0);
});
