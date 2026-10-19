(function(root){'use strict';
const S=root.Staff||(typeof module==='object'&&module.exports?require('./staff-model.js'):null),kinds={sale_cash:'فرۆشتنی کاش',sale_credit_cash:'کاشی پێشەکیی فرۆشتنی قەرز',collection:'وەرگرتنەوەی قەرز',full_refund:'گەڕاندنەوەی تەواو',partial_refund:'گەڕاندنەوەی بەشەکی'},limit=500000000000000000n;
const fail=()=>{throw Error('ڕاپۆرتی کاشی کاشێر پشتڕاست نەکرایەوە.');};
function day(v){if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(v))fail();const n=Date.parse(v+'T00:00:00Z');if(!Number.isFinite(n)||new Date(n).toISOString().slice(0,10)!==v)fail();return n;}
function range(from,to){const a=day(from),b=day(to);if(b<a||b-a>30*86400000)throw Error('ماوەیەکی دروست تا ٣١ ڕۆژ هەڵبژێرە.');return {from,to};}
function signed(v){if(typeof v!=='string'||!/^(-?[1-9][0-9]{0,18}|0)$/.test(v)||BigInt(v)>limit||BigInt(v)<-limit)fail();return BigInt(v);}
function report(v,owner,actor,from,to){
 range(from,to);if(!S.uuid(owner)||!S.uuid(actor)||v?.scope!=='cashier-cash-activity-v1'||v.owner_id!==owner||v.actor_id!==actor||!S.text(v.store_name,100)||!S.text(v.member_name,100)||v.currency!=='IQD'||v.timezone!=='Asia/Baghdad'||v.from!==from||v.to!==to||!S.date(v.generated_at)||!Array.isArray(v.rows)||v.rows.length>5000)fail();
 const localDate=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}),sums={sale_cash:0n,sale_credit_cash:0n,collection:0n,full_refund:0n,partial_refund:0n,inflow:0n,outflow:0n,net:0n,count:BigInt(v.rows.length)},seen=new Set();let prior=null;
 for(const row of v.rows){
  if(!S.uuid(row.id)||!Object.hasOwn(kinds,row.kind)||row.actor_id!==actor||!S.text(row.actor_name,100)||!S.date(row.created_at)||S.integer(row.number,9223372036854775807n)<1n)fail();
  const time=Date.parse(row.created_at),key=row.kind+':'+row.id,amount=S.integer(row.amount),out=['full_refund','partial_refund'].includes(row.kind),delta=signed(row.delta);
  const parts=localDate.formatToParts(new Date(time)),dateKey=['year','month','day'].map(k=>parts.find(x=>x.type===k).value).join('-');
  if(dateKey<from||dateKey>to||seen.has(key)||delta!==(out?-amount:amount))fail();
  if(prior&&(time>prior.time||time===prior.time&&(row.id>prior.id||row.id===prior.id&&row.kind>=prior.kind)))fail();
  prior={time,id:row.id,kind:row.kind};seen.add(key);sums[row.kind]+=amount;sums[out?'outflow':'inflow']+=amount;sums.net+=delta;
 }
 for(const [key,n] of Object.entries(sums))if(signed(v.summary?.[key])!==n)fail();return v;
}
function csv(v){const cell=x=>'"'+String(x).replaceAll('"','""')+'"',safe=x=>/^[=+\-@\t\r\n]/.test(String(x))?"'"+x:String(x),prefix=k=>k==='collection'?'D-':k.includes('refund')?'R-':'K-';return '\ufeff'+[['کاتی بەغدا','جۆر','ژمارەی بەڵگە','ئەنجامدەر','بڕ / دینار','گۆڕانی کاش / دینار'],...v.rows.map(r=>[new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'medium'}).format(new Date(r.created_at)),kinds[r.kind],prefix(r.kind)+r.number,safe(r.actor_name),r.amount,r.delta])].map(r=>r.map(cell).join(',')).join('\r\n');}
function ownerReport(v,owner,member,from,to){if(v?.scope!=='owner-cashier-cash-activity-v1'||v.viewer_id!==owner)fail();report({...v,scope:'cashier-cash-activity-v1'},owner,member,from,to);return v;}
root.StaffCash={range,report,ownerReport,csv,kinds,signed};if(typeof module==='object'&&module.exports)module.exports=root.StaffCash;
})(globalThis);
