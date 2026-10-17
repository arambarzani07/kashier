const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const id='00000000-0000-4000-8000-000000000003';
async function render(kind,record){
 const elements=new Map();class E{constructor(){this.children=[];this.events={};this.hidden=false;this.textContent='';this.dataset={};}append(...v){this.children.push(...v)}replaceChildren(...v){this.children=v}addEventListener(n,f){this.events[n]=f}}
 const get=s=>{if(!elements.has(s))elements.set(s,new E());return elements.get(s)};
 let finish;const done=new Promise(r=>finish=r);let prints=0;const document={querySelector:get,createElement:()=>new E(),body:new E()};document.body.dataset.receiptKind=kind;
 const api=async()=>{queueMicrotask(()=>queueMicrotask(finish));return record};
 vm.runInNewContext(fs.readFileSync(require.resolve('../receipt.js'),'utf8'),{document,KashierData:{loggedIn:()=>true,getSale:api,getPurchase:api},location:{search:'?id='+id},URLSearchParams,Intl,Date,window:{print:()=>prints++},requestAnimationFrame:f=>f()});await done; await new Promise(resolve=>setImmediate(resolve));
 const text=e=>e.textContent+' '+e.children.map(text).join(' ');
 assert.equal(get('#receipt-status').textContent,'');
 return {text:text(get('#receipt')),get,print:()=>{get('#print-receipt').events.click();return prints}};
}
test('saved sale receipt renders its immutable price and payment values',async()=>{const r=await render('sale',{id,receipt_no:12,created_at:'2026-10-17T07:00:00Z',currency:'IQD',customer_name:'Customer',note:'Saved note',subtotal:3000,discount:500,total:2500,received:5000,change_due:2500,lines:[{name:'Saved product',quantity_units:1000,unit_price:3000,line_total:3000}]});assert.match(r.text,/K-12/);assert.match(r.text,/3,000/);assert.match(r.text,/Customer/);assert.doesNotMatch(r.text,/undefined|NaN/);assert.equal(r.get('#print-receipt').disabled,false);assert.equal(r.print(),1);});
test('saved purchase receipt renders cost and supplier without inventing a cash payment',async()=>{const r=await render('purchase',{id,receipt_no:8,created_at:'2026-10-17T07:00:00Z',currency:'IQD',supplier_name:'Supplier',invoice_no:'INVOICE',note:'Purchase note',total:3000,lines:[{name:'Saved product',quantity_units:1500,unit_cost:2000,line_total:3000}]});assert.match(r.text,/P-8/);assert.match(r.text,/Supplier/);assert.match(r.text,/INVOICE/);assert.match(r.text,/2,000/);assert.doesNotMatch(r.text,/undefined|NaN|پارەی وەرگیراو|پارەی گەڕاندنەوە/);assert.equal(r.get('#print-receipt').disabled,false);});
