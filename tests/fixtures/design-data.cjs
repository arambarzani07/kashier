'use strict';
// Synthetic, in-process UI fixtures. Never imported by application code.
const seed=require('./design-data.json');
const owner='00000000-0000-4000-8000-000000000001';
const uuid=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const date='2026-10-21T09:00:00Z';
const longName='کاڵای تاقیکردنەوە بۆ پشکنینی ناوی درێژ و ڕێکخستنی نووسینی کوردی — پاکەت و کارتۆنی گەورە';
const longNote='تێبینی تاقیکردنەوە؛ ئەم داتایە ساختەیە و تەنها بۆ پشکنینی ڕووکار بەکاردێت. '.repeat(4);
const clone=x=>JSON.parse(JSON.stringify(x));
const products=Array.from({length:50},(_,i)=>({id:uuid(i+100),name:longName+' '+(i+1),barcode:'270000202'+String(9700+i),sale_price:1500+i,quantity_units:1250+i*1000,stock_version:i+1,expiry_date:'2026-10-20',reorder_units:5000,created_at:date}));
const people=Array.from({length:25},(_,i)=>({id:uuid(i+200),name:longName,phone:'07501234567',balance:25000,created_at:date}));
const entries=Array.from({length:25},(_,i)=>({id:uuid(i+300),movement_no:i+1,created_at:date,kind:'charge',amount:1000,delta:1000,balance_after:(i+1)*1000,note:longNote,customer_id:uuid(2),customer_name:people[0].name,supplier_id:uuid(2),supplier_name:people[0].name,sale_id:null,purchase_id:null,cash_movement_id:null}));
const lines=products.slice(0,15).map(p=>({product_id:p.id,name:p.name,barcode:p.barcode,quantity_units:1000,unit_price:1500,unit_cost:1500,line_total:1500}));
const sale={id:owner,receipt_no:9001234567,created_at:date,currency:'IQD',customer_name:people[0].name,note:longNote,subtotal:22500,discount:0,total:22500,received:23000,change_due:500,lines,payment_mode:'cash',customer_id:null,debt_amount:0,debt_entry_id:null};
const purchase={...sale,supplier_name:people[0].name,supplier_id:null,invoice_no:'INV-01234567890123456789',accounting_mode:'untracked',amount_paid:0,debt_amount:0};
const edge=process.env.KASHIER_UI_AUDIT_EDGE==='1';
if(edge){
 products.forEach(p=>{p.sale_price=1000000000;});
 people.forEach(p=>{p.balance=100000000000000;});
 entries.forEach((e,i)=>{e.amount=e.delta=4000000000000;e.balance_after=(i+1)*4000000000000;});
 lines.forEach(l=>{l.unit_price=l.unit_cost=l.line_total=1000000000;});
 Object.assign(sale,{subtotal:15000000000,total:15000000000,received:15000000000,change_due:0});
 Object.assign(purchase,{subtotal:sale.subtotal,total:sale.total,received:sale.received,change_due:0});
}
function decorate(x){if(Array.isArray(x))return x.map(decorate);if(x&&typeof x==='object')return Object.fromEntries(Object.entries(x).map(([k,v])=>[k,['name','customer_name','supplier_name','counterparty_name'].includes(k)&&typeof v==='string'?longName:['note','reason'].includes(k)&&typeof v==='string'?longNote:decorate(v)]));return x;}
function rpc(name,b={}){
 const map={get_dashboard_summary:'dashboard',get_daily_report:'daily',get_customer_statement:'statement',get_supplier_statement:'supplierStatement',get_customer_balances_report:'balances',get_supplier_balances_report:'balances',get_expense_report:'expense',get_expiry_report:'expiry',get_product_profile:'profile',get_customer_allocations:'allocations',get_sales_product_report:'salesReport',get_purchase_report:'purchaseReport',get_cash_statement:'cashStatement',get_stocktake_snapshot:'stocktake',get_return_document:'returnDocument',get_supplier_payables_report:'supplierPayables',export_owner_data:'exportPayload'};
 if(map[name]){
  const d=decorate(clone(seed[map[name]]));
  if(name==='get_daily_report')d.day=b.p_day;
  if(name==='get_customer_statement'||name==='get_supplier_statement'){(d.customer||d.supplier).id=b.p_customer||b.p_supplier;d.from=b.p_from;d.to=b.p_to;}
  if(name==='get_product_profile'){d.product.id=b.p_product;d.page=b.p_page||0;}
  if(name==='get_customer_allocations')d.customer.id=b.p_customer;
  if(name==='get_supplier_balances_report')d.party_kind='supplier';
  if(name.includes('balances_report')){d.query=b.p_query||'';d.debt_only=b.p_debt_only!==false;}
  if(name==='get_stocktake_snapshot')d.rows[0].id=products[0].id;
  if(name==='export_owner_data'){d.tables.products=products.map(p=>({...p,owner_id:owner}));d.counts.products=products.length;d.record_count=products.length;}
  return d;
 }
 if(name==='get_supplier_purchase_finance')return {purchase_id:b.p_purchase,receipt_no:'9001234567',invoice_no:'INV-TEST',supplier_id:null,supplier_name:longName,accounting_mode:'untracked',currency:'IQD',total:String(purchase.total),initial_paid:String(purchase.total),original_debt:'0',allocated_payments:'0',debt_reversed:'0',outstanding:'0'};
 if(name==='get_cash_summary')return {balance:edge?100000000000000:25000,count:25,sales:25000,deposits:1000,withdrawals:1000,expenses:1000,repayments:1000,refunds:1000,supplier_purchases:1000,supplier_payments:1000,supplier_refunds:1000};
 if(name==='get_debt_summary'||name==='get_supplier_summary')return {balance:edge?2500000000000000:625000,debtors:25,count:25};
 if(name==='get_supplier_activity')return {rows:entries.map(e=>({...e,source_type:'manual'})),total:25};
 if(name==='get_purchase_returns_report')return {rows:decorate(clone(seed.purchaseReturns)),count:2};
 if(name==='get_sale_returns_report')return {rows:decorate(clone(seed.purchaseReturns)).map(r=>({...r,sale_id:r.purchase_id,customer_name:people[0].name})),count:2};
 if(name==='search_receipts')return {rows:Array.from({length:20},(_,i)=>({...clone(b.p_kind==='purchase'?seed.purchaseSearch:seed.saleSearch),id:uuid(i+600),customer_name:people[0].name,supplier_name:people[0].name,receipt_no:String(9001234567+i)})),total:'20'};
 throw Error('No read-only UI fixture for RPC '+name);
}
function response(url,body){
 if(url.pathname==='/auth/v1/user')return {data:{id:owner,email:'ui-fixture@example.invalid'}};
 if(url.pathname.startsWith('/rest/v1/rpc/'))return {data:rpc(url.pathname.split('/').pop(),body)};
 const table=url.pathname.split('/').pop();let data;
 switch(table){
  case 'products':case 'stock_catalog':case 'low_stock_catalog': data=clone(products);break;
  case 'customer_debt_catalog':case 'supplier_debt_catalog':data=clone(people);break;
  case 'debt_entries':case 'supplier_entries':data=clone(entries);break;
  case 'cash_movements':data=entries.map(e=>({...e,kind:'deposit'}));break;
  case 'stock_movements':data=entries.map((e,i)=>({...e,product_id:products[0].id,delta_units:1000,balance_after:(i+1)*1000,purchase_id:owner}));break;
  case 'stock_adjustments':data=entries.map(e=>({...e,adjustment_no:e.movement_no,product_id:products[0].id,product_name:longName,kind:'count',delta_units:1000,after_units:25000}));break;
  case 'sales':data=[clone(sale)];break;
  case 'purchases':data=[clone(purchase)];break;
  case 'sale_reversals':case 'sale_returns':case 'purchase_reversals':case 'purchase_returns':data=[];break;
  default:throw Error('No read-only UI fixture for table '+table);
 }
 const barcode=url.searchParams.get('barcode');if(barcode?.startsWith('eq.'))data=data.filter(p=>p.barcode===barcode.slice(3));
 const ids=url.searchParams.get('id');if(ids?.startsWith('in.(')){const wanted=ids.slice(4,-1).split(',');data=data.filter(p=>wanted.includes(p.id));}
 const id=url.searchParams.get('id');if(id?.startsWith('eq.'))data=[{...data[0],id:id.slice(3)}];
 return {data,headers:{'content-range':`0-${Math.max(0,data.length-1)}/${data.length}`}};
}
module.exports={owner,uuid,products,people,seed,sale,purchase,response,rpc,longName,longNote};
