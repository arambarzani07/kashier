(function(root){
 'use strict';
 const sessionKey='kashier.auth.v1';
 const messages={
  supplier_auth_required:'سەرەتا بچۆ ژوورەوە.',
  supplier_purchase_unavailable:'ئەم پسوولەی کڕینە نەدۆزرایەوە یان دەسەڵاتت نییە.',
  supplier_purchase_no_payable:'ئەم کڕینە قەرزی دابینکەری بۆ پارەدان نییە.',
  supplier_purchase_ledger_mismatch:'حسابی قەرزی ئەم کڕینە یەک ناگرێتەوە؛ کردارەکە وەستێنرا.',
  supplier_purchase_already_paid:'قەرزی ئەم کڕینە بە تەواوی دراوە.',
  supplier_purchase_overpayment:'بڕی پارەدان لە قەرزی ماوەی ئەم کڕینە زیاترە.',
  supplier_invalid_amount:'بڕی پارەدان نادروستە.',
  supplier_note_required:'هۆکاری پارەدان بنووسە.',
  supplier_request_conflict:'ناسنامەی پارەدان پێشتر بۆ مامەڵەیەکی تر بەکارهاتووە.',
  cash_insufficient_balance:'پارەی بەردەستی قاسە بەس نییە.'
 };
 function token(){try{return JSON.parse(sessionStorage.getItem(sessionKey)||'null')?.access_token||'';}catch{return '';}}
 async function auth(){if(!root.KashierData?.loggedIn?.())throw new Error(messages.supplier_auth_required);await root.KashierData.getAccount();const value=token();if(!value)throw new Error(messages.supplier_auth_required);return value;}
 async function rpc(name,body){const access=await auth();let response;try{response=await fetch(root.KashierConfig.url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:root.KashierConfig.publishableKey,Authorization:'Bearer '+access,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});}catch{throw new Error('پەیوەندی بە سێرڤەر نەکرا؛ دۆخی پارەدان پشتڕاست نییە.');}const text=await response.text();let data=null;try{data=text?JSON.parse(text):null;}catch{throw new Error('وەڵامی سێرڤەر نەخوێندرایەوە.');}if(!response.ok){const code=data?.message||data?.code;const error=new Error(messages[code]||(response.status===401?messages.supplier_auth_required:'پارەدانی قەرزی کڕین تەواو نەبوو.'));error.status=response.status;error.code=code;throw error;}return data;}
 function validId(value){return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value||'');}
 function validateFinance(data,purchase){if(!data||data.purchase_id!==purchase||!['tracked','untracked'].includes(data.accounting_mode)||data.currency!=='IQD')throw new Error('حسابی قەرزی کڕین پشتڕاست نەکرایەوە.');for(const key of ['total','initial_paid','original_debt','allocated_payments','debt_reversed','outstanding'])if(typeof data[key]!=='string'||!/^\d+$/.test(data[key]))throw new Error('بڕی حسابی کڕین نادروستە.');const total=BigInt(data.total),initial=BigInt(data.initial_paid),debt=BigInt(data.original_debt),allocated=BigInt(data.allocated_payments),reversed=BigInt(data.debt_reversed),outstanding=BigInt(data.outstanding);if(initial+debt!==total||allocated+reversed+outstanding!==debt||outstanding<0n)throw new Error('کۆی حسابی قەرزی کڕین یەک ناگرێتەوە.');if(data.supplier_id!==null&&!validId(data.supplier_id))throw new Error('ناسنامەی دابینکەر نادروستە.');return data;}
 async function getFinance(purchase){if(!validId(purchase))throw new Error(messages.supplier_purchase_unavailable);return validateFinance(await rpc('get_supplier_purchase_finance',{p_purchase:purchase}),purchase);}
 async function postPayment(payload){if(!validId(payload?.p_id)||!validId(payload?.p_purchase))throw new Error(messages.supplier_purchase_unavailable);if(!Number.isSafeInteger(payload.p_amount)||payload.p_amount<1||payload.p_amount>100000000000000)throw new Error(messages.supplier_invalid_amount);if(typeof payload.p_note!=='string'||payload.p_note.trim().length<1||payload.p_note.trim().length>500)throw new Error(messages.supplier_note_required);const data=await rpc('post_supplier_purchase_payment',{...payload,p_note:payload.p_note.trim()});if(data?.entry?.id!==payload.p_id||data?.entry?.purchase_id!==payload.p_purchase)throw new Error('وەڵامی پارەدان پشتڕاست نەکرایەوە.');data.finance=validateFinance(data.finance,payload.p_purchase);return data;}
 root.KashierPurchasePayment={getFinance,postPayment};
})(globalThis);
