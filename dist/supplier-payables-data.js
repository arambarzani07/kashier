(function(root){
 'use strict';
 const sessionKey='kashier.auth.v1';
 const messages={supplier_auth_required:'سەرەتا بچۆ ژوورەوە.',supplier_payables_invalid_supplier:'ناوی دابینکەر زۆر درێژە.',supplier_payables_invalid_query:'گەڕان زۆر درێژە؛ تا ١٠٠ پیت بنووسە.',supplier_payables_invalid_amount:'بڕی قەرز نادروستە.',supplier_payables_invalid_amount_range:'بڕی کەم نابێت لە بڕی زۆر زیاتر بێت.',supplier_payables_invalid_page:'ژمارەی پەڕە نادروستە.'};
 function readToken(){try{return JSON.parse(sessionStorage.getItem(sessionKey)||'null')?.access_token||'';}catch{return '';}}
 async function token(){if(!root.KashierData?.loggedIn?.())throw new Error(messages.supplier_auth_required);await root.KashierData.getAccount();const value=readToken();if(!value)throw new Error(messages.supplier_auth_required);return value;}
 function amount(value){if(value===null||value===undefined||value==='')return null;const number=Number(value);if(!Number.isSafeInteger(number)||number<0||number>100000000000000)throw new Error(messages.supplier_payables_invalid_amount);return number;}
 async function list({supplier='',query='',minOutstanding=null,maxOutstanding=null,page=0,limit=50}={}){
  supplier=String(supplier||'').trim();query=String(query||'').trim();if(supplier.length>100)throw new Error(messages.supplier_payables_invalid_supplier);if(query.length>100)throw new Error(messages.supplier_payables_invalid_query);
  const min=amount(minOutstanding),max=amount(maxOutstanding);if(min!==null&&max!==null&&min>max)throw new Error(messages.supplier_payables_invalid_amount_range);if(!Number.isInteger(page)||page<0||!Number.isInteger(limit)||limit<1||limit>100)throw new Error(messages.supplier_payables_invalid_page);
  const access=await token();let response;try{response=await fetch(root.KashierConfig.url+'/rest/v1/rpc/get_supplier_payables_report',{method:'POST',headers:{apikey:root.KashierConfig.publishableKey,Authorization:'Bearer '+access,'Content-Type':'application/json'},body:JSON.stringify({p_supplier:supplier||null,p_query:query||null,p_min_outstanding:min,p_max_outstanding:max,p_offset:page*limit,p_limit:limit}),signal:AbortSignal.timeout(20000)});}catch{throw new Error('پەیوەندی بە سێرڤەر نەکرا؛ ئینتەرنێتەکەت بپشکنە.');}
  const text=await response.text();let data=null;try{data=text?JSON.parse(text):null;}catch{throw new Error('وەڵامی سێرڤەر نەخوێندرایەوە.');}if(!response.ok){const code=data?.message||data?.code;const error=new Error(messages[code]||(response.status===401?messages.supplier_auth_required:'قەرزە ماوەکانی دابینکەر نەخوێندرایەوە.'));error.status=response.status;error.code=code;throw error;}
  if(!data||!Array.isArray(data.rows)||!/^\d+$/.test(String(data.count)))throw new Error('وەڵامی ناوەندی قەرزەکان گونجاو نییە.');return data;
 }
 root.KashierSupplierPayables={list};
})(globalThis);
