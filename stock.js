'use strict';
const $=s=>document.querySelector(s),productId=new URLSearchParams(location.search).get('product');
let page=0,query='',requestNumber=0;const format=n=>new Intl.NumberFormat('en-US',{maximumFractionDigits:3}).format(n);
function el(tag,text){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;}
async function load(){
 if(!KashierData.loggedIn()){location.replace('auth.html?next=stock.html');return;}
 const request=++requestNumber;$('#stock-status').textContent='خوێندنەوەی کۆگا…';$('#stock-rows').replaceChildren();$('#previous').disabled=true;$('#next').disabled=true;
 try{
  const movements=Boolean(productId);if(movements&&!/^[0-9a-f-]{36}$/i.test(productId))throw new Error('ناسنامەی کاڵا نادروستە.');
  const {rows,total}=movements?await KashierData.listStockMovements(productId,page):await KashierData.listStock(query,page);if(request!==requestNumber)return;
  $('#stock-title').textContent=movements?'جووڵەکانی کۆگا':'کۆگا';$('#stock-search').hidden=movements;const header=el('tr');for(const text of movements?['بەروار','جووڵە','بڕی گۆڕان','بڕی دوای جووڵە','پسوولە']:['کاڵا','بارکۆد','بڕی بەردەست','کردار'])header.append(el('th',text));$('#stock-head').replaceChildren(header);
  for(const item of rows){const row=el('tr');if(movements){for(const text of [new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'medium'}).format(new Date(item.created_at)),item.purchase_id?'کڕین':'فرۆشتن',(item.delta_units>0?'+':'')+format(item.delta_units/1000),format(item.balance_after/1000)])row.append(el('td',text));const action=el('td'),link=el('a','بینین');link.className='catalog-link';link.href=(item.purchase_id?'purchase-receipt.html?id='+item.purchase_id:'receipt.html?id='+item.sale_id);action.append(link);row.append(action);}else{for(const text of [item.name,item.barcode||'—',format(item.quantity_units/1000)])row.append(el('td',text));const action=el('td'),link=el('a','جووڵەکان');link.href='stock.html?product='+item.id;link.className='catalog-link';action.append(link);row.append(action);}$('#stock-rows').append(row);}
  $('#stock-status').textContent=rows.length?'':movements?'هێشتا جووڵەیەک تۆمار نەکراوە.':'هیچ کاڵایەک نەدۆزرایەوە.';$('#stock-count').textContent='کۆ: '+total+' · پەڕە: '+(page+1);$('#previous').disabled=page===0;$('#next').disabled=(page+1)*50>=total;
 }catch(e){if(request===requestNumber)$('#stock-status').textContent=e.message;}
}
$('#stock-search').addEventListener('submit',e=>{e.preventDefault();query=$('#stock-query').value;page=0;load();});$('#previous').addEventListener('click',()=>{if(page>0){page--;load();}});$('#next').addEventListener('click',()=>{page++;load();});load();
