const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const math=require('../sale-math.js');
const user='00000000-0000-4000-8000-000000000001',product='00000000-0000-4000-8000-000000000002',id='00000000-0000-4000-8000-000000000003';
const key='kashier.purchase-draft.v1.'+user;
function setup(post,{saved,storageFails=false,cost=2000}={}){
 const nodes=new Map();
 class E{constructor(){this.value='';this.children=[];this.events={};this.hidden=false;this.textContent='';this.classList={toggle(){}};}append(...v){this.children.push(...v)}replaceChildren(...v){this.children=v}addEventListener(k,f){this.events[k]=f}setAttribute(){}checkValidity(){return true}showModal(){}close(){}}
 const get=s=>{if(!nodes.has(s))nodes.set(s,new E());return nodes.get(s)};
 const memory=saved||{[key]:JSON.stringify({version:1,items:[{productId:product,name:'test only',barcode:'ROLLBACK',quantityUnits:1500,price:cost}],supplier:'Supplier test',invoice:'Invoice test',note:'Note test',posting:null})};
 const storage={getItem:k=>memory[k]||null,setItem:(k,v)=>{if(storageFails)throw Error('unavailable');memory[k]=v},removeItem:k=>delete memory[k]};
 const calls=[],location={href:'',replace(v){this.href=v}};
 const context={document:{querySelector:get,querySelectorAll:()=>[get('#supplier'),get('#invoice'),get('#purchase-note'),get('#purchase-query')],createElement:()=>new E(),body:new E()},SaleMath:math,KashierData:{userId:()=>user,loggedIn:()=>true,postPurchase:async p=>{calls.push(JSON.parse(JSON.stringify(p)));return post(p)}},sessionStorage:storage,Intl,Date,crypto:{randomUUID:()=>id},location};
 vm.runInNewContext(fs.readFileSync(require.resolve('../purchase.js'),'utf8'),context);
 return {get,memory,calls,location,click:()=>get('#post-purchase').events.click()};
}
test('ordinary purchase draft restores supplier, invoice and note',()=>{const x=setup(async p=>({id:p.p_id}));assert.equal(x.get('#supplier').value,'Supplier test');assert.equal(x.get('#invoice').value,'Invoice test');assert.equal(x.get('#purchase-note').value,'Note test');assert.equal(x.get('#purchase-total').textContent,'3,000');});
test('uncertain purchase retries preserve ID and quantity without duplicate stock intent',async()=>{let first=true;const x=setup(async p=>{if(first){first=false;throw Error('lost response');}return {id:p.p_id};});await x.click();assert.equal(x.get('#supplier').disabled,true);assert.ok(JSON.parse(x.memory[key]).posting);await x.click();assert.deepEqual(x.calls[0],x.calls[1]);assert.equal(x.calls[0].p_items[0].quantity_units,1500);assert.match(x.location.href,/purchase-receipt\.html\?id=.*print=1/);assert.equal(x.memory[key],undefined);});
test('purchase journal survives same-tab reload',async()=>{const a=setup(async()=>{throw Error('timeout');});await a.click();const b=setup(async p=>({id:p.p_id}),{saved:a.memory});await b.click();assert.deepEqual(a.calls[0],b.calls[0]);});
test('purchase cannot post without a unit cost or durable tab journal',async()=>{const a=setup(async p=>({id:p.p_id}),{cost:0});await a.click();assert.equal(a.calls.length,0);const b=setup(async p=>({id:p.p_id}),{storageFails:true});await b.click();assert.equal(b.calls.length,0);});
test('definite purchase rejection unlocks editing',async()=>{const x=setup(async()=>{const e=Error('missing product');e.status=400;e.saleCode='purchase_product_unavailable';throw e;});await x.click();assert.equal(x.get('#supplier').disabled,false);assert.equal(JSON.parse(x.memory[key]).posting,null);});
test('repeated purchase clicks share one in-flight request',async()=>{let resolve;const x=setup(p=>new Promise(r=>resolve=()=>r({id:p.p_id})));const pending=x.click();await x.click();assert.equal(x.calls.length,1);resolve();await pending;});
