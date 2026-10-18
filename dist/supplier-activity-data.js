(function(root){
 'use strict';
 const sessionKey='kashier.auth.v1';
 const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
 function readToken(){try{return JSON.parse(sessionStorage.getItem(sessionKey)||'null')?.access_token||'';}catch{return '';}}
 async function token(){if(!root.KashierData?.loggedIn?.())throw new Error('سەرەتا بچۆ ژوورەوە.');await root.KashierData.getAccount();const value=readToken();if(!value)throw new Error('سەرەتا بچۆ ژوورەوە.');return value;}
 async function listSupplierActivity(supplierId,page=0){if(!uuid(supplierId))throw new Error('ناسنامەی دابینکەر نادروستە.');if(!Number.isInteger(page)||page<0)throw new Error('ژمارەی پەڕە نادروستە.');const access=await token();let response;try{response=await fetch(root.KashierConfig.url+'/rest/v1/rpc/get_supplier_activity',{method:'POST',headers:{apikey:root.KashierConfig.publishableKey,Authorization:'Bearer '+access,'Content-Type':'application/json'},body:JSON.stringify({p_supplier:supplierId,p_offset:page*50,p_limit:50}),signal:AbortSignal.timeout(20000)});}catch{throw new Error('پەیوەندی بە سێرڤەر نەکرا؛ ئینتەرنێتەکەت بپشکنە.');}const text=await response.text();let data=null;try{data=text?JSON.parse(text):null;}catch{throw new Error('وەڵامی سێرڤەر نەخوێندرایەوە.');}if(!response.ok){const code=data?.message;if(response.status===401)throw new Error('سێشنەکەت کۆتایی هاتووە؛ دووبارە بچۆ ژوورەوە.');if(code==='supplier_unavailable')throw new Error('دابینکەر نەدۆزرایەوە یان دەسەڵاتت نییە.');throw new Error('مێژووی حسابی دابینکەر نەخوێندرایەوە.');}return {rows:Array.isArray(data?.rows)?data.rows:[],total:Number(data?.total)||0};}
 if(root.KashierData)root.KashierData.getSupplierEntries=listSupplierActivity;
 root.KashierSupplierActivity={list:listSupplierActivity};
})(globalThis);
