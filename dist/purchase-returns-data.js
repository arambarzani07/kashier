(function(root){
 'use strict';
 const sessionKey='kashier.auth.v1';
 const messages={
  purchase_returns_auth_required:'سەرەتا بچۆ ژوورەوە.',
  purchase_returns_invalid_kind:'جۆری گەڕاندنەوە نادروستە.',
  purchase_returns_invalid_dates:'بەرواری سەرەتا نابێت دوای بەرواری کۆتایی بێت.',
  purchase_returns_invalid_supplier:'ناوی دابینکەر زۆر درێژە.',
  purchase_returns_invalid_query:'گەڕان زۆر درێژە؛ تا ١٠٠ پیت بنووسە.',
  purchase_returns_invalid_amount:'بڕی پارە نادروستە.',
  purchase_returns_invalid_amount_range:'بڕی کەم نابێت لە بڕی زۆر زیاتر بێت.',
  purchase_returns_invalid_page:'ژمارەی پەڕە نادروستە.'
 };
 function readToken(){try{return JSON.parse(sessionStorage.getItem(sessionKey)||'null')?.access_token||'';}catch{return '';}}
 async function getToken(){if(!root.KashierData?.loggedIn?.())throw new Error(messages.purchase_returns_auth_required);await root.KashierData.getAccount();const token=readToken();if(!token)throw new Error(messages.purchase_returns_auth_required);return token;}
 function money(value){if(value===null||value===undefined||value==='')return null;const number=Number(value);if(!Number.isInteger(number)||number<0||number>100000000000000)throw new Error(messages.purchase_returns_invalid_amount);return number;}
 async function list({kind='all',from=null,to=null,supplier='',query='',minAmount=null,maxAmount=null,page=0,limit=50}={}){
  if(!['all','full','partial'].includes(kind))throw new Error(messages.purchase_returns_invalid_kind);
  if(from&&to&&from>to)throw new Error(messages.purchase_returns_invalid_dates);
  supplier=String(supplier||'').trim();query=String(query||'').trim();
  if(supplier.length>100)throw new Error(messages.purchase_returns_invalid_supplier);
  if(query.length>100)throw new Error(messages.purchase_returns_invalid_query);
  const min=money(minAmount),max=money(maxAmount);
  if(min!==null&&max!==null&&min>max)throw new Error(messages.purchase_returns_invalid_amount_range);
  if(!Number.isInteger(page)||page<0||!Number.isInteger(limit)||limit<1||limit>100)throw new Error(messages.purchase_returns_invalid_page);
  const token=await getToken();let response;
  try{
   response=await fetch(root.KashierConfig.url+'/rest/v1/rpc/get_purchase_returns_report',{
    method:'POST',headers:{apikey:root.KashierConfig.publishableKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},
    body:JSON.stringify({p_kind:kind,p_from:from||null,p_to:to||null,p_supplier:supplier||null,p_query:query||null,p_min_amount:min,p_max_amount:max,p_offset:page*limit,p_limit:limit}),
    signal:AbortSignal.timeout(20000)
   });
  }catch{throw new Error('پەیوەندی بە سێرڤەر نەکرا؛ ئینتەرنێتەکەت بپشکنە.');}
  const text=await response.text();let data=null;try{data=text?JSON.parse(text):null;}catch{throw new Error('وەڵامی سێرڤەر نەخوێندرایەوە.');}
  if(!response.ok){const code=data?.message||data?.code;const error=new Error(messages[code]||(response.status===401?'سێشنەکەت کۆتایی هاتووە؛ دووبارە بچۆ ژوورەوە.':'ناوەندی گەڕاندنەوەکانی کڕین نەخوێندرایەوە.'));error.status=response.status;error.code=code;throw error;}
  if(!data||!Array.isArray(data.rows)||!/^\d+$/.test(String(data.count)))throw new Error('وەڵامی ناوەندی گەڕاندنەوەکان گونجاو نییە.');
  return {rows:data.rows,total:Number(data.count)};
 }
 root.KashierPurchaseReturns={list};
})(globalThis);
