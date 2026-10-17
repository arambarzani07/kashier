const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const math=require('../sale-math.js');
const user='00000000-0000-4000-8000-000000000001',product='00000000-0000-4000-8000-000000000002',request='00000000-0000-4000-8000-000000000003';
const key='kashier.sale-draft.v2.'+user;
function setup(postSale,{saved,storageFails=false,manual=false}={}){
 const elements=new Map();
 class E{constructor(){this.value='';this.children=[];this.events={};this.hidden=false;this.disabled=false;this.textContent='';this.classList={toggle(){}};}append(...nodes){this.children.push(...nodes)}replaceChildren(...nodes){this.children=nodes}addEventListener(n,f){this.events[n]=f}setAttribute(){}focus(){}showModal(){}close(){}checkValidity(){return true}querySelector(){return get('#scan-submit')}}
 const get=s=>{if(!elements.has(s))elements.set(s,new E());return elements.get(s)};
 get('#discount').value='0';get('#received').value='0';
 const memory=saved||{[key]:JSON.stringify({version:1,items:[{name:'test-only',barcode:'TEST',productId:manual?undefined:product,quantityUnits:1000,price:8000}],customer:'',note:'',discount:'0',received:'10000'})};
 const storage={getItem:k=>memory[k]||null,setItem:(k,v)=>{if(storageFails)throw Error('storage unavailable');memory[k]=v;},removeItem:k=>delete memory[k]};
 const location={href:''},calls=[];
 const context={document:{querySelector:get,createElement:()=>new E(),querySelectorAll:()=>[get('#barcode'),get('#received'),get('#discount'),get('#customer'),get('#note')],body:new E()},sessionStorage:storage,SaleMath:math,KashierData:{userId:()=>user,loggedIn:()=>true,postSale:async p=>{calls.push(JSON.parse(JSON.stringify(p)));return postSale(p);}},Intl,Date,crypto:{randomUUID:()=>request},location,window:{print(){}}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../sale.js'),'utf8'),context);
 return {get,memory,calls,location,click:()=>get('#post-sale').events.click()};
}
test('uncertain posting locks editing and retry uses the same ID and payload',async()=>{
 let first=true;const x=setup(async p=>{if(first){first=false;throw Error('connection lost');}return {id:p.p_id};});
 await x.click();assert.equal(x.get('#barcode').disabled,true);assert.equal(x.get('#post-sale').disabled,false);assert.ok(JSON.parse(x.memory[key]).posting);
 await x.click();assert.deepEqual(x.calls[0],x.calls[1]);assert.match(x.location.href,/receipt\.html\?id=.*print=1/);assert.equal(x.memory[key],undefined);
});
test('reload recovers the pending request instead of making a new sale ID',async()=>{
 const first=setup(async()=>{throw Error('timeout');});await first.click();const previous=first.calls[0];
 const second=setup(async p=>({id:p.p_id}),{saved:first.memory});await second.click();assert.deepEqual(second.calls[0],previous);
});
test('definitive price rejection unlocks draft for correction',async()=>{
 const x=setup(async()=>{const e=Error('price changed');e.status=400;e.saleCode='sale_price_changed';throw e;});await x.click();assert.equal(x.get('#barcode').disabled,false);assert.equal(JSON.parse(x.memory[key]).posting,null);assert.equal(x.location.href,'');
});
test('repeated clicks while request is in flight send only once',async()=>{
 let resolve;const x=setup(p=>new Promise(r=>resolve=()=>r({id:p.p_id})));const pending=x.click();await x.click();assert.equal(x.calls.length,1);resolve();await pending;
});
test('cannot post when the retry journal cannot be saved',async()=>{
 const x=setup(async p=>({id:p.p_id}),{storageFails:true});await x.click();assert.equal(x.calls.length,0);assert.equal(x.location.href,'');
});
test('manual draft lines cannot be posted as catalog sales',async()=>{
 const x=setup(async p=>({id:p.p_id}),{manual:true});await x.click();assert.equal(x.calls.length,0);assert.equal(x.get('#post-sale').disabled,true);
});
