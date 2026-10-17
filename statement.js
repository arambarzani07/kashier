'use strict';
const isSupplier=document.body?.dataset?.accountKind==='supplier',paymentKind=isSupplier?'payment':'repayment';
const $=selector=>document.querySelector(selector),customerId=new URLSearchParams(location.search).get('id');
const uuid=value=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value||'');
const format=value=>new Intl.NumberFormat('en-US').format(BigInt(value));
const date=value=>new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'short'}).format(new Date(value));
let statement=null,requestNumber=0;
function node(tag,text,className){const element=document.createElement(tag);if(text!==undefined)element.textContent=text;if(className)element.className=className;return element;}
function invalidate(){requestNumber++;statement=null;$('#statement-paper').hidden=true;$('#statement-paper').replaceChildren();$('#statement-print').disabled=true;$('#statement-load').disabled=false;$('#statement-status').textContent='بۆ پیشاندانی کشفی ئەم ماوەیە دوگمەی پیشاندان دابگرە.';}
function validDate(value){if(!value)return true;if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||value<'0001-01-01')return false;try{return new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;}catch{return false;}}
function validate(data,from,to){
 if(!data||(isSupplier?data.supplier:data.customer)?.id!==customerId||data.from!==from||data.to!==to||data.currency!=='IQD'||data.timezone!=='Asia/Baghdad'||!Array.isArray(data.rows)||data.count!==data.rows.length||data.rows.length>5000)throw Error('کشفەکە تەواو نییە یان وەڵامەکە پشتڕاست نەکرایەوە.');
 const integer=value=>{if(typeof value!=='string'||! /^-?\d+$/.test(value))throw Error('بڕی حساب نادروستە.');return BigInt(value);};
 let balance=integer(data.opening),charges=0n,repayments=0n,reversals=0n,last=0n;
 for(const row of data.rows){const amount=integer(row.amount),delta=integer(row.delta),order=integer(row.movement_no);if(amount<=0n||order<=last||!['charge',paymentKind,'reversal'].includes(row.kind)||delta!==(row.kind==='charge'?amount:-amount))throw Error('ڕیزبەندی یان بڕی مامەڵە نادروستە.');last=order;balance+=delta;if(balance!==integer(row.balance))throw Error('باڵانسی مامەڵەکان یەک ناگرێتەوە.');if(row.kind==='charge')charges+=amount;else if(row.kind===paymentKind)repayments+=amount;else reversals+=amount;}
 if(balance!==integer(data.closing)||charges!==integer(data.charges)||repayments!==integer(isSupplier?data.payments:data.repayments)||reversals!==integer(data.reversals))throw Error('کۆی حساب یەک ناگرێتەوە.');
 date(data.generated_at);
}
function render(data){
 const profile=isSupplier?data.supplier:data.customer;const paper=$('#statement-paper');paper.replaceChildren(node('h2','کاشێر'),node('h3',isSupplier?'کشفی حسابی دابینکەر':'کشفی حسابی کڕیار'));
 const meta=node('div',undefined,'statement-meta');meta.append(node('div',(isSupplier?'دابینکەر: ':'کڕیار: ')+profile.name));if(profile.phone)meta.append(node('div','مۆبایل: '+profile.phone));meta.append(node('div','ماوە: '+(data.from||'لە سەرەتاوە')+' — '+(data.to||'تا کاتی خوێندنەوە')),node('div','کاتی خوێندنەوە: '+date(data.generated_at)+' · بەغدا'),node('div','دراو: دیناری عێراقی / IQD · ژمارەی مامەڵە: '+data.count));paper.append(meta);
 const totals=node('div',undefined,'statement-totals');for(const [label,value] of [['باڵانسی سەرەتا',data.opening],['کۆی قەرزی زیادکراو',data.charges],[isSupplier?'پارەی دراو بە دابینکەر':'کۆی پارەی وەرگیراو',isSupplier?data.payments:data.repayments],['قەرزی هەڵوەشاوە بە گەڕاندنەوە',data.reversals],['باڵانسی کۆتایی',data.closing]].filter((row,index)=>!isSupplier||index!==3)){const cell=node('div');cell.append(node('span',label),node('strong',format(value),'numeric'));totals.append(cell);}paper.append(totals);
 if(!data.rows.length)paper.append(node('p','لەو ماوەیەدا هیچ مامەڵەیەک تۆمار نەکراوە.','statement-empty'));
 else{const wrap=node('div',undefined,'statement-table-wrap'),table=node('table'),head=node('thead'),header=node('tr');table.append(node('caption','قەرز، پارەدان و گەڕاندنەوەکان بە ڕیزبەندی تۆمارکردن','sr-only'));for(const title of ['تۆمار','بەروار / بەغدا','جۆر','قەرز زیادکراو',isSupplier?'پارەی دراو':'پارەی وەرگیراو','قەرزی هەڵوەشاوە','باڵانس','تێبینی'].filter((label,index)=>!isSupplier||index!==5)){const th=node('th',title);th.scope='col';header.append(th);}head.append(header);table.append(head);const body=node('tbody');for(const entry of data.rows){const row=node('tr'),source=node('td','D-'+entry.movement_no);if(isSupplier&&uuid(entry.purchase_id)){const link=node('a','پسوولەی کڕین');link.href='purchase-receipt.html?id='+entry.purchase_id;source.append(node('br'),link);}if(uuid(entry.sale_id)){const link=node('a','پسوولە');link.href='receipt.html?id='+entry.sale_id;source.append(node('br'),link);}const kind=entry.kind===paymentKind?(isSupplier?'پارەدان بە دابینکەر':'پارەدان'):entry.kind==='reversal'?'گەڕاندنەوەی فرۆشتن':entry.purchase_id?'قەرزی کڕین':entry.sale_id?'قەرزی فرۆشتن':'قەرزی دەستی';row.append(source,node('td',date(entry.created_at)),node('td',kind),node('td',entry.kind==='charge'?format(entry.amount):'—','numeric'),node('td',entry.kind===paymentKind?format(entry.amount):'—','numeric'),...(!isSupplier?[node('td',entry.kind==='reversal'?format(entry.amount):'—','numeric')]:[]),node('td',format(entry.balance),'numeric'),node('td',entry.note));body.append(row);}table.append(body);wrap.append(table);paper.append(wrap);}
 paper.append(node('p',isSupplier?'ئەم حسابە قەرزمان بۆ دابینکەر پیشان دەدات. پارەدان لە حسابی گشتی دابینکەر کەم دەبێتەوە؛ بە پسوولەیەکی دیاریکراو نەبەستراوەتەوە.':'باڵانسەکان تایبەتن بە ماوەی دیاریکراو. پارەدان لە حسابی گشتی کڕیار کەم دەبێتەوە؛ گەڕاندنەوەی فرۆشتنی قەرزیش وەک تۆمارێکی پێچەوانە قەرز کەم دەکات و تۆماری سەرەکی ناسڕێتەوە.','statement-footnote'));paper.hidden=false;
}
async function load(){
 invalidate();const request=++requestNumber;$('#statement-status').textContent='';
 if(!uuid(customerId)){$('#statement-status').textContent='ناسنامەی کڕیار نادروستە؛ لە لیستی کڕیارەکانەوە هەڵیبژێرە.';return;}
 if(!KashierData.loggedIn()){location.replace('auth.html?next='+encodeURIComponent((isSupplier?'supplier-statement.html?id=':'statement.html?id=')+customerId));return;}
 const from=$('#statement-from').value||null,to=$('#statement-to').value||null;
 if(!$('#statement-form').reportValidity()||!validDate(from)||!validDate(to)||(from&&to&&from>to)){$('#statement-status').textContent='بەروارەکان بپشکنە؛ سەرەتا نابێت دوای کۆتایی بێت.';return;}
 $('#statement-load').disabled=true;$('#statement-status').textContent='خوێندنەوەی کشفی حساب…';
 try{const data=await (isSupplier?KashierData.getSupplierStatement(customerId,from,to):KashierData.getCustomerStatement(customerId,from,to));if(request!==requestNumber)return;validate(data,from,to);render(data);statement=data;$('#statement-status').textContent='کشفەکە تەواوە. بۆ زانیاری نوێ دوگمەی نوێکردنەوە دابگرە.';$('#statement-print').disabled=false;}
 catch(error){if(request===requestNumber){statement=null;$('#statement-paper').hidden=true;$('#statement-print').disabled=true;$('#statement-status').textContent=error.message;}}
 finally{if(request===requestNumber)$('#statement-load').disabled=false;}
}
$('#statement-form').addEventListener('submit',event=>{event.preventDefault();load();});
for(const selector of ['#statement-from','#statement-to'])$(selector).addEventListener('input',invalidate);
$('#statement-all').addEventListener('click',()=>{$('#statement-from').value='';$('#statement-to').value='';load();});
$('#statement-print').addEventListener('click',()=>{if(statement&&!$('#statement-print').disabled)window.print();});
if(uuid(customerId)){$('#back-customer').href=(isSupplier?'supplier.html?id=':'customer.html?id=')+customerId;$('#back-customer').textContent=isSupplier?'حسابی دابینکەر ←':'حسابی کڕیار ←';}
load();
