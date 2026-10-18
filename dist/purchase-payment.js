(function(){
 'use strict';
 const purchase=new URLSearchParams(location.search).get('id'),key='kashier.purchase-payment-draft.'+purchase;
 const $=s=>document.querySelector(s),money=v=>new Intl.NumberFormat('en-US').format(BigInt(v||0));let currentOutstanding=0n;
 function uuid(){if(globalThis.crypto?.randomUUID)return globalThis.crypto.randomUUID();const b=new Uint8Array(16);globalThis.crypto.getRandomValues(b);b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;const h=[...b].map(x=>x.toString(16).padStart(2,'0')).join('');return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20);}
 function read(){try{return JSON.parse(sessionStorage.getItem(key)||'null');}catch{return null;}}
 function save(value){try{if(value)sessionStorage.setItem(key,JSON.stringify(value));else sessionStorage.removeItem(key);return true;}catch{return false;}}
 function status(text){$('#purchase-payment-status').textContent=text||'';}
 function parseAmount(value){const raw=String(value||'').trim();if(!/^\d+$/.test(raw))return null;const n=Number(raw);return Number.isSafeInteger(n)&&n>=1&&n<=100000000000000?n:null;}
 function render(finance){const panel=$('#purchase-payment-panel'),form=$('#purchase-payment-form'),info=$('#purchase-payment-info');panel.hidden=false;form.hidden=true;status('');
  $('#purchase-payment-total').textContent=money(finance.total)+' دینار';$('#purchase-payment-initial').textContent=money(finance.initial_paid)+' دینار';$('#purchase-payment-allocated').textContent=money(finance.allocated_payments)+' دینار';$('#purchase-payment-outstanding').textContent=money(finance.outstanding)+' دینار';
  const outstanding=BigInt(finance.outstanding),debt=BigInt(finance.original_debt);currentOutstanding=outstanding;$('#purchase-payment-amount').max=finance.outstanding;
  if(finance.accounting_mode!=='tracked'||!finance.supplier_id||debt===0n){save(null);info.textContent='ئەم پسوولەیە قەرزی دابینکەری بەستراو نییە.';return;}
  if(outstanding===0n){save(null);info.textContent='قەرزی ئەم کڕینە بە تەواوی دراوە ✅';return;}
  form.hidden=false;info.textContent='قەرزی ماوەی ئەم پسوولەیە '+money(finance.outstanding)+' دینارە. ئەم پارەدانە تەنها بە هەمان پسوولە دەبەسترێت و لە قاسە کەم دەبێتەوە.';
  const draft=read();if(draft){$('#purchase-payment-amount').value=String(draft.amount||'');$('#purchase-payment-note').value=draft.note||'';status('دۆخی پارەدانی پێشوو پشتڕاست نەبوو؛ retry بە هەمان ناسنامە پارێزراوە.');}
 }
 async function load(){const panel=$('#purchase-payment-panel');if(!panel)return;if(!KashierData.loggedIn()){panel.hidden=true;return;}panel.hidden=false;$('#purchase-payment-form').hidden=true;$('#purchase-payment-info').textContent='خوێندنەوەی حسابی قەرزی کڕین…';try{render(await KashierPurchasePayment.getFinance(purchase));}catch(error){$('#purchase-payment-info').textContent='حسابی قەرزی کڕین پشتڕاست نەکرایەوە.';status(error.message);}}
 $('#purchase-payment-form')?.addEventListener('submit',async event=>{event.preventDefault();const button=$('#purchase-payment-submit');if(button.disabled)return;const amount=parseAmount($('#purchase-payment-amount').value),note=$('#purchase-payment-note').value.trim();if(!amount){status('بڕی پارەدان بە دیناری تەواو و زیاتر لە سفر بنووسە.');return;}if(!note){status('هۆکاری پارەدان بنووسە.');return;}let draft=read();if(draft){if(draft.amount!==amount||draft.note!==note){status('پارەدانی ماوە بڕ یان تێبینی جیاوازی هەیە؛ زانیاری پێشووی هەمان داواکاری بەکاربهێنە.');return;}}else{if(BigInt(amount)>currentOutstanding){status('بڕی پارەدان لە قەرزی ماوەی ئەم کڕینە زیاترە.');return;}draft={id:uuid(),amount,note};if(!save(draft)){status('ناسنامەی پارێزراوی پارەدان هەڵنەگیرا؛ کردارەکە نەنێردرا.');return;}}
  if(!confirm('دڵنیایت '+money(String(amount))+' دینار بۆ قەرزی ئەم پسوولەی کڕینە بدەیت؟'))return;button.disabled=true;status('تۆمارکردنی پارەدان…');try{const result=await KashierPurchasePayment.postPayment({p_id:draft.id,p_purchase:purchase,p_amount:draft.amount,p_note:draft.note});save(null);$('#purchase-payment-amount').value='';$('#purchase-payment-note').value='';render(result.finance);window.dispatchEvent(new CustomEvent('kashier:purchase-finance-changed',{detail:{purchase_id:purchase,finance:result.finance}}));}catch(error){if(error.status&&error.status<500&&error.code!=='supplier_request_conflict')save(null);status(error.message);}finally{button.disabled=false;}
 });
 $('#purchase-payment-refresh')?.addEventListener('click',load);
 load();
})();
