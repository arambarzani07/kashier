(function(root){
 'use strict';
 const sessionKey='kashier.auth.v1';
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 function readToken(){try{return JSON.parse(sessionStorage.getItem(sessionKey)||'null')?.access_token||'';}catch{return '';}}
 async function getToken(){if(!root.KashierData?.loggedIn?.())throw new Error('سەرەتا بچۆ ژوورەوە.');await root.KashierData.getAccount();const token=readToken();if(!token)throw new Error('سەرەتا بچۆ ژوورەوە.');return token;}
 function normalize(value){
  const input=String(value??'').trim().toUpperCase().replace(/\s+/g,'');
  const match=/^(?:K-?)?([0-9]{1,19})$/.exec(input);
  if(!match)throw new Error('ژمارەی پسوولە بنووسە یان بارکۆدی K-123 بسکەنە.');
  const receipt=BigInt(match[1]);
  if(receipt<1n||receipt>9223372036854775807n)throw new Error('ژمارەی پسوولە لە سنووری ڕێگەپێدراو نییە.');
  return receipt.toString();
 }
 function digits(value){return typeof value==='string'&&/^\d+$/.test(value);}
 function validRow(row,receipt){
  if(!row||!uuid.test(row.id)||String(row.receipt_no)!==receipt||!Number.isFinite(Date.parse(row.created_at)))return false;
  if(typeof row.customer_name!=='string'||row.customer_name.length>100||!['cash','credit'].includes(row.payment_mode))return false;
  if(!digits(String(row.total))||!digits(String(row.discount))||!digits(String(row.debt_amount??0)))return false;
  return true;
 }
 async function find(value){
  const receipt=normalize(value),token=await getToken();
  const params=new URLSearchParams({select:'id,receipt_no,created_at,customer_name,total,payment_mode,debt_amount,discount',receipt_no:'eq.'+receipt,limit:'2'});
  let response;try{response=await fetch(root.KashierConfig.url+'/rest/v1/sales?'+params,{headers:{apikey:root.KashierConfig.publishableKey,Authorization:'Bearer '+token},signal:AbortSignal.timeout(20000)});}catch{throw new Error('پەیوەندی بە سێرڤەر نەکرا؛ ئینتەرنێتەکەت بپشکنە.');}
  const text=await response.text();let data=null;try{data=text?JSON.parse(text):null;}catch{throw new Error('وەڵامی سێرڤەر نەخوێندرایەوە.');}
  if(!response.ok){const error=new Error(response.status===401?'سێشنەکەت کۆتایی هاتووە؛ دووبارە بچۆ ژوورەوە.':'پسوولەکە نەخوێندرایەوە.');error.status=response.status;throw error;}
  if(!Array.isArray(data)||data.length>1)throw new Error('وەڵامی پسوولە گونجاو نییە.');
  if(!data.length)return null;
  if(!validRow(data[0],receipt))throw new Error('زانیاری پسوولە گونجاو نییە.');
  return data[0];
 }
 root.KashierReturnLookup={normalize,find};
})(globalThis);
