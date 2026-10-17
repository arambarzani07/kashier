const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const math=require('../sale-math.js');
const owner='00000000-0000-4000-8000-000000000001',id='00000000-0000-4000-8000-000000000003',key='kashier.cash-draft.v1.'+owner;
function setup(post,{saved,storageFails=false,summary={balance:'0',sales:'0',deposits:'0',withdrawals:'0',expenses:'0',count:'0'}}={}){
 const elements=new Map();class E{constructor(){this.value='';this.children=[];this.events={};this.hidden=false;this.textContent='';this.dataset={};}append(...v){this.children.push(...v)}replaceChildren(...v){this.children=v}addEventListener(k,f){this.events[k]=f}showModal(){this.open=true}close(){this.open=false}reportValidity(){return true}}
 const get=s=>{if(!elements.has(s))elements.set(s,new E());return elements.get(s)};get('#cash-kind').value='deposit';get('#cash-amount').value='1000';get('#cash-note').value='cash test reason';
 const memory=saved||{},calls=[];const storage={getItem:k=>memory[k]||null,setItem:(k,v)=>{if(storageFails)throw Error('storage failure');memory[k]=v},removeItem:k=>delete memory[k]};
 const context={document:{querySelector:get,querySelectorAll:s=>s==='[data-cash-lock]'?[get('#cash-kind'),get('#cash-amount'),get('#cash-note')]:[],createElement:()=>new E()},KashierData:{userId:()=>owner,loggedIn:()=>true,getCashSummary:async()=>summary,listCashEntries:async()=>({rows:[],total:0}),postCashEntry:async p=>{calls.push(JSON.parse(JSON.stringify(p)));return post(p)}},SaleMath:math,Intl,Date,sessionStorage:storage,crypto:{randomUUID:()=>id},URLSearchParams,location:{search:'',replace(){}},window:{print(){}}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../cash.js'),'utf8'),context);
 return {get,memory,calls,submit:()=>get('#cash-form').events.submit({preventDefault(){}})};
}
function entry(p){return {id:p.p_id,movement_no:1,created_at:'2026-10-17T07:00:00Z',kind:p.p_kind,amount:p.p_amount,delta:p.p_amount,balance_after:p.p_amount,note:p.p_note,sale_id:null};}
test('cash retry keeps original ID and amount after an ambiguous response',async()=>{let first=true;const x=setup(async p=>{if(first){first=false;throw Error('timeout');}return entry(p)});await x.submit();assert.equal(x.get('#cash-amount').disabled,true);assert.ok(JSON.parse(x.memory[key]).posting);await x.submit();assert.deepEqual(x.calls[0],x.calls[1]);assert.equal(x.memory[key],undefined);assert.equal(x.get('#cash-detail-dialog').open,true);});
test('same-tab reload restores a pending cash entry',async()=>{const a=setup(async()=>{throw Error('timeout')});await a.submit();const b=setup(async p=>entry(p),{saved:a.memory});await b.submit();assert.deepEqual(a.calls[0],b.calls[0]);});
test('definitive insufficient-cash rejection unlocks fields',async()=>{const x=setup(async()=>{const e=Error('not enough cash');e.status=400;e.saleCode='cash_insufficient_balance';throw e});await x.submit();assert.equal(x.get('#cash-amount').disabled,false);assert.equal(JSON.parse(x.memory[key]).posting,null);assert.equal(x.get('#cash-detail-dialog').open,undefined);});
test('repeated cash submit while in flight sends only once',async()=>{let resolve;const x=setup(p=>new Promise(r=>resolve=()=>r(entry(p))));const pending=x.submit();await x.submit();assert.equal(x.calls.length,1);resolve();await pending;});
test('cash entry is not sent if its retry journal cannot be saved',async()=>{const x=setup(async p=>entry(p),{storageFails:true});await x.submit();assert.equal(x.calls.length,0);});
test('zero cash amount and whitespace-only reason are rejected',async()=>{const x=setup(async p=>entry(p));x.get('#cash-amount').value='0';await x.submit();assert.equal(x.calls.length,0);x.get('#cash-amount').value='1000';x.get('#cash-note').value='   ';await x.submit();assert.equal(x.calls.length,0);});
test('large lifetime summary strings render without numeric precision loss',async()=>{const x=setup(async p=>entry(p),{summary:{balance:'0',sales:'9007199254740993',deposits:'0',withdrawals:'0',expenses:'0',count:'0'}});await new Promise(r=>setImmediate(r));assert.equal(x.get('#cash-sales').textContent,'9,007,199,254,740,993');});
