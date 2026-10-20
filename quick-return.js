'use strict';
const $=selector=>document.querySelector(selector);
let requestNumber=0;
const money=value=>new Intl.NumberFormat('en-US').format(BigInt(String(value??0)))+' دینار';
const when=value=>new Intl.DateTimeFormat('ckb-IQ-u-ca-gregory-nu-latn',{timeZone:'Asia/Baghdad',dateStyle:'medium',timeStyle:'short'}).format(new Date(value));
function hideActions(){for(const id of ['partial-return-action','full-return-action','return-document-action'])$("#"+id).hidden=true;}
function clearResult(){const box=$('#quick-return-result');box.hidden=true;hideActions();$('#quick-return-state').className='quick-return-state';}
function setState(text,kind=''){$('#quick-return-state').textContent=text;$('#quick-return-state').className='quick-return-state'+(kind?' '+kind:'');}
function receiptHref(sale,hash=''){return 'receipt.html?id='+encodeURIComponent(sale.id)+(hash||'');}
function renderBase(sale){
 $('#quick-return-result-title').textContent='K-'+sale.receipt_no;
 $('#quick-return-date').textContent=when(sale.created_at);
 $('#quick-return-customer').textContent=sale.customer_name||'—';
 $('#quick-return-mode').textContent=sale.payment_mode==='credit'?'قەرز':'کاش';
 $('#quick-return-total').textContent=money(sale.total);
 $('#open-receipt').href=receiptHref(sale);
 hideActions();
 $('#quick-return-result').hidden=false;
}
function sumCash(returns){let total=0n;for(const item of returns)total+=BigInt(String(item.cash_refund??0));return total;}
function renderState(sale,reversal,returns,stateError){
 renderBase(sale);
 const note=$('#quick-return-note'),partial=$('#partial-return-action'),full=$('#full-return-action'),documentLink=$('#return-document-action'),discounted=BigInt(String(sale.discount??0))>0n;
 if(stateError){setState('دۆخ ناپشتڕاستە','warn');note.textContent='پسوولە دۆزرایەوە، بەڵام دۆخی گەڕاندنەوە پشتڕاست نەکرایەوە. بۆ پاراستنی حساب هیچ کردارێک لێرە چالاک ناکرێت؛ پسوولەکە بکەرەوە و نوێکردنەوە بکە.';return;}
 if(reversal){setState('گەڕێندراوەتەوە','done');note.textContent='ئەم فرۆشتنە پێشتر بە تەواوی گەڕێندراوەتەوە · R-'+reversal.reversal_no+' · '+money(reversal.cash_refund)+' کاش · '+money(reversal.debt_reversed)+' قەرز.';documentLink.href='return-document.html?source=sale&kind=full&id='+encodeURIComponent(reversal.id);documentLink.hidden=false;return;}
 if(returns.length){setState('گەڕاندنەوەی بەشێک: '+returns.length,'warn');note.textContent='ئەم پسوولەیە '+returns.length+' گەڕاندنەوەی بەشی هەیە؛ کۆی پارەی گەڕاوە '+money(sumCash(returns))+' ـە. گەڕاندنەوەی تەواو بە یاسای حسابداری قوفڵە.';if(sale.payment_mode==='cash'){partial.href=receiptHref(sale,'#partial-return-panel');partial.hidden=false;if(discounted)note.textContent+=' پارەی گەڕاندنەوەی بەشی بە دابەشکردنی داشکاندن لە بەهای خاوێن حساب دەکرێت.';}else note.textContent+=' گەڕاندنەوەی بەشێکی فرۆشتنی قەرز هێشتا قوفڵە.';return;}
 setState('ئامادە','');
 full.href=receiptHref(sale,'#reversal-panel');full.hidden=false;
 if(sale.payment_mode==='cash'){partial.href=receiptHref(sale,'#partial-return-panel');partial.hidden=false;note.textContent=discounted?'پسوولەکە داشکاندنی هەیە. گەڕاندنەوەی تەواو و بەشێک هەردووکیان چالاکن؛ پارەی گەڕاندنەوەی بەشی بە دابەشکردنی وردی بەهای خاوێن حساب دەکرێت.':'پسوولەکە هیچ گەڕاندنەوەیەکی پێشووی نییە. دەتوانیت گەڕاندنەوەی تەواو یان بەشێک هەڵبژێریت.';}
 else note.textContent='ئەمە فرۆشتنی قەرزە. گەڕاندنەوەی تەواو بە پێی یاساکانی پاراستنی قەرز کار دەکات؛ گەڕاندنەوەی بەشێک تا تەواوبوونی دابەشکردنی پارەدان قوفڵە.';
}
async function findReceipt(event){
 event?.preventDefault();
 const input=$('#receipt-code'),button=$('#find-receipt'),status=$('#quick-return-status'),request=++requestNumber;
 clearResult();button.disabled=true;input.disabled=true;status.textContent='پسوولەکە دەگەڕێندرێتەوە…';
 try{
  const sale=await KashierReturnLookup.find(input.value);
  if(request!==requestNumber)return;
  if(!sale){status.textContent='هیچ پسوولەیەک بەو ژمارەیە لە هەژمارەکەت نەدۆزرایەوە.';input.focus();input.select();return;}
  const states=await Promise.allSettled([KashierData.getSaleReversal(sale.id),KashierData.listSaleReturns(sale.id)]);
  if(request!==requestNumber)return;
  const reversal=states[0].status==='fulfilled'?states[0].value:null;
  const returns=states[1].status==='fulfilled'?states[1].value:[];
  const stateError=states.filter(item=>item.status==='rejected').map(item=>item.reason?.message||'').filter(Boolean).join(' ');
  renderState(sale,reversal,returns,stateError);
  status.textContent='K-'+sale.receipt_no+' دۆزرایەوە.';
 }catch(error){if(request!==requestNumber)return;status.textContent=(globalThis.KashierLocale?.message(error.message)??error.message);clearResult();if(error.status===401){location.replace('auth.html?next='+encodeURIComponent('quick-return.html'));return;}input.focus();input.select();}
 finally{if(request===requestNumber){button.disabled=false;input.disabled=false;}}
}
if(!KashierData.loggedIn())location.replace('auth.html?next='+encodeURIComponent('quick-return.html'));
else{$('#quick-return-form').addEventListener('submit',findReceipt);$('#receipt-code').addEventListener('input',()=>{if($('#quick-return-result').hidden)return;clearResult();$('#quick-return-status').textContent='ژمارەکە گۆڕا؛ دۆزینەوە بکە.';});requestAnimationFrame(()=>$('#receipt-code').focus());}
