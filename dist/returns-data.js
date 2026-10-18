(function(root){
 'use strict';
 const sessionKey='kashier.auth.v1';
 const messages={
  returns_auth_required:'سەرەتا بچۆ ژوورەوە.',
  returns_invalid_kind:'جۆری گەڕاندنەوە نادروستە.',
  returns_invalid_dates:'بەرواری سەرەتا نابێت دوای بەرواری کۆتایی بێت.',
  returns_invalid_page:'ژمارەی پەڕە نادروستە.',
  returns_invalid_query:'گەڕان زۆر درێژە؛ تا ١٠٠ پیت بنووسە.'
 };
 function readToken(){try{return JSON.parse(sessionStorage.getItem(sessionKey)||'null')?.access_token||'';}catch{return '';}}
 async function getToken(){if(!root.KashierData?.loggedIn?.())throw new Error('سەرەتا بچۆ ژوورەوە.');await root.KashierData.getAccount();const token=readToken();if(!token)throw new Error('سەرەتا بچۆ ژوورەوە.');return token;}
 async function list({kind='all',from=null,to=null,query='',page=0,limit=50}={}){
  if(!Number.isInteger(page)||page<0||!Number.isInteger(limit)||limit<1||limit>100)throw new Error(messages.returns_invalid_page);
  const token=await getToken();
  let response;try{response=await fetch(root.KashierConfig.url+'/rest/v1/rpc/get_sale_returns_report',{method:'POST',headers:{apikey:root.KashierConfig.publishableKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({p_kind:kind,p_from:from||null,p_to:to||null,p_query:query.trim()||null,p_offset:page*limit,p_limit:limit}),signal:AbortSignal.timeout(20000)});}catch{throw new Error('پەیوەندی بە سێرڤەر نەکرا؛ ئینتەرنێتەکەت بپشکنە.');}
  const text=await response.text();let data=null;try{data=text?JSON.parse(text):null;}catch{throw new Error('وەڵامی سێرڤەر نەخوێندرایەوە.');}
  if(!response.ok){const code=data?.message||data?.code;const error=new Error(messages[code]||(response.status===401?'سێشنەکەت کۆتایی هاتووە؛ دووبارە بچۆ ژوورەوە.':'ڕاپۆرتی گەڕاندنەوەکان نەخوێندرایەوە.'));error.status=response.status;error.code=code;throw error;}
  if(!data||!Array.isArray(data.rows)||!/^\d+$/.test(String(data.count)))throw new Error('وەڵامی ڕاپۆرت گونجاو نییە.');
  return {rows:data.rows,total:Number(data.count)};
 }
 root.KashierReturns={list};
})(globalThis);
