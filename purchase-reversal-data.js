(function(root){
 'use strict';
 const sessionKey='kashier.auth.v1';
 const messages={
  purchase_reversal_auth_required:'سەرەتا بچۆ ژوورەوە.',
  purchase_reversal_invalid_request:'داواکاری گەڕاندنەوەی کڕین نادروستە.',
  purchase_reversal_reason_required:'هۆکاری گەڕاندنەوە بنووسە، تا ٥٠٠ پیت.',
  purchase_reversal_unavailable:'پسوولەی کڕین نەدۆزرایەوە یان دەسەڵاتت نییە.',
  purchase_reversal_already_exists:'ئەم پسوولەی کڕینە پێشتر بە تەواوی گەڕێندراوەتەوە.',
  purchase_reversal_request_conflict:'ناسنامەی ئەم داواکارییە پێشتر بە زانیاریی جیاواز بەکارهاتووە.',
  purchase_reversal_credit_unsupported:'ئەم کڕینە قەرزی دابینکەری هەیە؛ تا پارەدانەکان بە پسوولە دیاری نەکرێن، گەڕاندنەوەی تەواو قوفڵە.',
  purchase_reversal_state_invalid:'دۆخی دارایی ئەم پسوولەیە بۆ گەڕاندنەوە گونجاو نییە.',
  purchase_reversal_stock_insufficient:'هەموو کاڵاکانی ئەم کڕینە لە کۆگا بەردەست نین؛ گەڕاندنەوە تۆمار نەکرا.',
  purchase_reversal_cash_limit:'پارەی قاسە دوای گەڕاندنەوە لە سنووری ڕێگەپێدراو زیاتر دەبێت.'
 };
 const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
 function readToken(){try{return JSON.parse(sessionStorage.getItem(sessionKey)||'null')?.access_token||'';}catch{return '';}}
 async function token(){if(!root.KashierData?.loggedIn?.())throw new Error('سەرەتا بچۆ ژوورەوە.');await root.KashierData.getAccount();const value=readToken();if(!value)throw new Error('سەرەتا بچۆ ژوورەوە.');return value;}
 async function request(path,{method='GET',body,prefer}={}){const access=await token();let response;try{response=await fetch(root.KashierConfig.url+path,{method,headers:{apikey:root.KashierConfig.publishableKey,Authorization:'Bearer '+access,'Content-Type':'application/json',...(prefer?{Prefer:prefer}:{})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(20000)});}catch{throw new Error('پەیوەندی بە سێرڤەر نەکرا؛ ئینتەرنێتەکەت بپشکنە.');}const text=await response.text();let data=null;try{data=text?JSON.parse(text):null;}catch{throw new Error('وەڵامی سێرڤەر نەخوێندرایەوە.');}if(!response.ok){const code=data?.message||data?.code;const error=new Error(messages[code]||(response.status===401?'سێشنەکەت کۆتایی هاتووە؛ دووبارە بچۆ ژوورەوە.':'داواکاری گەڕاندنەوەی کڕین تەواو نەبوو.'));error.status=response.status;error.code=code;throw error;}return {data,response};}
 async function get(purchaseId){if(!uuid(purchaseId))throw new Error('ناسنامەی پسوولەی کڕین نادروستە.');const params=new URLSearchParams({select:'id,reversal_no,purchase_id,supplier_id,supplier_name,created_at,reason,accounting_mode,total,cash_refund,lines',purchase_id:'eq.'+purchaseId,limit:'1'});const {data}=await request('/rest/v1/purchase_reversals?'+params);return data[0]||null;}
 async function post(payload){if(!payload||!uuid(payload.p_id)||!uuid(payload.p_purchase))throw new Error(messages.purchase_reversal_invalid_request);const {data}=await request('/rest/v1/rpc/post_purchase_reversal',{method:'POST',body:payload});return data;}
 async function listCashEntries(kind='',page=0){const allowed=['sale','deposit','withdrawal','expense','repayment','refund','supplier_purchase','supplier_payment','supplier_refund'];if(kind&&!allowed.includes(kind))throw new Error('جۆری مامەڵە نادروستە.');if(!Number.isInteger(page)||page<0)throw new Error('ژمارەی پەڕە نادروستە.');const params=new URLSearchParams({select:'id,movement_no,created_at,kind,amount,delta,balance_after,sale_id,customer_id,supplier_id,purchase_id,reversal_id,return_id,purchase_reversal_id,purchase_reversal:purchase_reversals(purchase_id),note',order:'movement_no.desc',limit:'50',offset:String(page*50)});if(kind)params.set('kind','eq.'+kind);const {data,response}=await request('/rest/v1/cash_movements?'+params,{prefer:'count=exact'});const total=Number(response.headers.get('content-range')?.split('/')[1]);const rows=data.map(({purchase_reversal,...row})=>({...row,purchase_id:row.purchase_id||purchase_reversal?.purchase_id||null}));return {rows,total:Number.isFinite(total)?total:0};}
 async function listStockMovements(productId,page=0){if(!uuid(productId))throw new Error('ناسنامەی کاڵا نادروستە.');if(!Number.isInteger(page)||page<0)throw new Error('ژمارەی پەڕە نادروستە.');const params=new URLSearchParams({select:'id,movement_no,created_at,product_id,delta_units,balance_after,purchase_id,sale_id,reversal_id,return_id,adjustment_id,purchase_reversal_id,adjustment:stock_adjustments(note,kind),reversal:sale_reversals(sale_id),returned:sale_returns(sale_id),purchase_reversal:purchase_reversals(purchase_id)',product_id:'eq.'+productId,order:'movement_no.desc',limit:'50',offset:String(page*50)});const {data,response}=await request('/rest/v1/stock_movements?'+params,{prefer:'count=exact'});const total=Number(response.headers.get('content-range')?.split('/')[1]);const rows=data.map(({purchase_reversal,...row})=>({...row,purchase_reversal_purchase_id:purchase_reversal?.purchase_id||null}));return {rows,total:Number.isFinite(total)?total:0};}
 if(root.KashierData){root.KashierData.listCashEntries=listCashEntries;root.KashierData.listStockMovements=listStockMovements;}
 root.KashierPurchaseReversal={get,post};
})(globalThis);
