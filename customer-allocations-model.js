(function(root){'use strict';
const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
function money(v,max=null){if(typeof v!=='string'||! /^(0|[1-9][0-9]*)$/.test(v))throw Error('بڕی پارە نادروستە.');const n=BigInt(v);if(max!==null&&n>max)throw Error('بڕی پارە لە سنوور زیاترە.');return n;}
// User input accepts local digits; server snapshots and saved requests stay strict ASCII.
function inputAmount(value){
 if(typeof value!=='string')throw Error('بڕی پارە نادروستە.');
 const digits=value.trim().replace(/[٠-٩۰-۹]/g,c=>String(c.charCodeAt(0)-(c<='٩'?0x660:0x6f0)));
 if(!/^[0-9]{1,15}$/.test(digits))throw Error('بڕ بە ژمارەی تەواو بنووسە، بەبێ خاڵ یان کۆما.');
 const amount=BigInt(digits);
 if(amount<1n||amount>100000000000000n)throw Error('بڕی پارە لە سنووری ڕێگەپێدراو نییە.');
 return amount.toString();
}
function validate(data,customer,owner){const fail=()=>{throw Error('وەڵامی دابەشکردنی پارەدان تەواو نییە یان یەک ناگرێتەوە.');};
 if(!data||data.customer?.id!==customer||data.owner_id!==owner||typeof data.customer.name!=='string'||!data.customer.name.trim()||data.currency!=='IQD'||data.timezone!=='Asia/Baghdad'||!Number.isFinite(Date.parse(data.generated_at))||!Array.isArray(data.entries)||data.entries.length>5000||!Array.isArray(data.allocations)||data.allocations.length>5000)fail();
 const entries=new Map(),used=new Map(),seen=new Set(),reversals=new Set();let last=0n,charges=0n,payments=0n,capacity=0n,unallocated=0n;
 for(const e of data.entries){if(!uuid(e?.id)||entries.has(e.id)||!['charge','repayment'].includes(e.kind)||typeof e.note!=='string'||!Number.isFinite(Date.parse(e.created_at))||e.sale_id!==null&&!uuid(e.sale_id))fail();const amount=money(e.amount,100000000000000n),allocated=money(e.allocated),reversed=money(e.reversed),available=money(e.available),order=money(e.movement_no);if(amount<1n||order<=last||amount!==allocated+reversed+available||e.kind==='repayment'&&(e.sale_id!==null||reversed!==0n))fail();last=order;entries.set(e.id,e);used.set(e.id,0n);if(e.kind==='charge'){charges+=amount-reversed;capacity+=available;}else{payments+=amount;unallocated+=available;}}
 for(const a of data.allocations){if(!uuid(a?.id)||seen.has(a.id)||typeof a.note!=='string'||!a.note.trim()||!Number.isFinite(Date.parse(a.created_at)))fail();seen.add(a.id);const payment=entries.get(a.payment_entry_id),charge=entries.get(a.charge_entry_id),amount=money(a.amount,100000000000000n);if(payment?.kind!=='repayment'||charge?.kind!=='charge'||amount<1n)fail();if(a.reversal_id!==null){if(!uuid(a.reversal_id)||reversals.has(a.reversal_id)||typeof a.reversal_reason!=='string'||!a.reversal_reason.trim()||!Number.isFinite(Date.parse(a.reversed_at)))fail();reversals.add(a.reversal_id);}else{if(a.reversal_reason!==null||a.reversed_at!==null)fail();used.set(payment.id,used.get(payment.id)+amount);used.set(charge.id,used.get(charge.id)+amount);}}
 for(const e of data.entries)if(used.get(e.id)!==money(e.allocated))fail();const balance=money(data.balance,100000000000000n);if(charges-payments!==balance||capacity-unallocated!==balance)fail();return {data,entries,capacity,unallocated,balance};
}
root.CustomerAllocations={uuid,money,inputAmount,validate};if(typeof module==='object'&&module.exports)module.exports=root.CustomerAllocations;
})(globalThis);
