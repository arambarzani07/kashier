(function(root){'use strict';
const S=root.Staff||(typeof module==='object'&&module.exports?require('./staff-model.js'):null);
const R=root.StaffRefund||(typeof module==='object'&&module.exports?require('./staff-refund-model.js'):null);
const fail=()=>{throw Error('زانیاریی گەڕاندنەوەی بەشی پشتڕاست نەکرایەوە.');};
function allocations(sale){
 let cumulative=0n,prior=0n;
 return sale.lines.map((line,i)=>{
  cumulative+=BigInt(line.line_total);
  const allocated=sale.discount===0?0n:BigInt(sale.discount)*cumulative/BigInt(sale.subtotal);
  const discount=allocated-prior;prior=allocated;
  return {line_no:i+1,discount,net:BigInt(line.line_total)-discount,quantity:BigInt(line.quantity_units),price:BigInt(line.unit_price)};
 });
}
function cumulative(a,qty,discounted){return discounted?a.net*qty/a.quantity:(qty*a.price+500n)/1000n;}
function context(value,sale){
 if(!value||!Array.isArray(value.states)||value.states.length!==sale.lines.length)fail();
 const count=S.integer(value.count,9223372036854775807n),parts=allocations(sale);let units=0n;
 value.states.forEach((state,i)=>{
  if(state.line_no!==i+1)fail();
  const qty=S.integer(state.returned_units,10000000n),amount=S.integer(state.refunded);
  if(qty>parts[i].quantity||amount!==cumulative(parts[i],qty,sale.discount>0))fail();
  units+=qty;
 });
 if((count===0n&&units!==0n)||count>units)fail();
 return value;
}
function sameContext(a,b){return a?.count===b?.count&&Array.isArray(a.states)&&Array.isArray(b.states)&&a.states.length===b.states.length&&a.states.every((v,i)=>['line_no','returned_units','refunded'].every(k=>v[k]===b.states[i][k]));}
function source(s,owner,actor,id,no){
 R.identity(s,'cashier-partial-source-v1',owner,actor);S.receipt(s.sale,actor,id||s.sale?.id);
 if(no&&String(s.sale.receipt_no)!==no||typeof s.can_partial_refund!=='boolean'||!(s.full_refund_id===null||S.uuid(s.full_refund_id)))fail();
 context(s.context,s.sale);
 return {...s,eligible:s.can_partial_refund&&s.full_refund_id===null&&s.context.states.some((v,i)=>BigInt(v.returned_units)<BigInt(s.sale.lines[i].quantity_units))};
}
function preview(s,lines){
 context(s.context,s.sale);
 if(!Array.isArray(lines)||lines.length<1||lines.length>200)fail();
 const parts=allocations(s.sale);let prior=0,total=0n;
 for(const line of lines){
  if(!Number.isInteger(line.line_no)||line.line_no<=prior||line.line_no>parts.length)fail();prior=line.line_no;
  const q=S.integer(line.quantity_units,10000000n),a=parts[line.line_no-1],old=BigInt(s.context.states[line.line_no-1].returned_units);
  if(q<1n||old+q>a.quantity)fail();
  total+=cumulative(a,old+q,s.sale.discount>0)-cumulative(a,old,s.sale.discount>0);
 }
 if(total>100000000000000n)fail();return total;
}
function payload(p,owner,s){
 if(p?.p_owner!==owner||!S.uuid(p.p_id)||!S.uuid(p.p_sale)||!S.text(p.p_reason,500)||p.p_reason!==p.p_reason.trim())fail();
 S.integer(p.p_expected_count,9223372036854775807n);
 if(s&&(p.p_sale!==s.sale.id||p.p_expected_count!==s.context.count))fail();
 if(s)preview(s,p.p_lines);else if(!Array.isArray(p.p_lines)||!p.p_lines.length)fail();
 return p;
}
function pending(v,owner,actor){
 if(v?.version!==1||v.owner!==owner||v.actor!==actor||v.acknowledged!==true)fail();
 const s=source(v.source,owner,actor,v.payload?.p_sale);
 if(!s.eligible)fail();payload(v.payload,owner,s);return v;
}
function document(s,owner,actor,id,p,original){
 R.identity(s,'cashier-partial-return-v1',owner,actor);S.receipt(s.sale,actor,s.sale?.id);
 const z=s.returned;
 if(!S.uuid(z?.id)||z.id!==id||z.sale_id!==s.sale.id||z.actor_id!==actor||!S.text(z.actor_name,100)||!S.date(z.created_at)||!S.text(z.reason,500)||z.reason!==z.reason.trim()||z.currency!=='IQD'||S.integer(z.return_no,9223372036854775807n)<1n||!Number.isSafeInteger(z.total)||z.total<0||z.cash_refund!==z.total||z.debt_reversed!==0||!Array.isArray(z.lines)||!z.lines.length||z.lines.length>s.sale.lines.length)fail();
 context(z.staff_context,s.sale);
 if(original&&(!R.sameSale(s.sale,original.sale)||!sameContext(z.staff_context,original.context)))fail();
 const parts=allocations(s.sale),seen=new Set(),requested=[];
 for(const line of z.lines){
  if(!Number.isInteger(line.line_no)||line.line_no<1||line.line_no>parts.length||seen.has(line.line_no))fail();seen.add(line.line_no);
  const a=parts[line.line_no-1],base=s.sale.lines[line.line_no-1],old=BigInt(z.staff_context.states[line.line_no-1].returned_units);
  if(!Number.isSafeInteger(line.quantity_units)||line.quantity_units<1)fail();
  const qty=BigInt(line.quantity_units);
  if(old+qty>a.quantity||['product_id','name','unit_price'].some(k=>line[k]!==base[k])||(line.barcode??null)!==(base.barcode??null)||line.original_quantity_units!==base.quantity_units||line.original_line_total!==base.line_total||line.allocated_discount!==Number(a.discount)||line.net_line_total!==Number(a.net)||line.line_total!==Number(cumulative(a,old+qty,s.sale.discount>0)-cumulative(a,old,s.sale.discount>0)))fail();
  requested.push({line_no:line.line_no,quantity_units:String(line.quantity_units)});
 }
 requested.sort((a,b)=>a.line_no-b.line_no);
 if(preview({sale:s.sale,context:z.staff_context},requested)!==BigInt(z.total))fail();
 if(p&&(z.sale_id!==p.p_sale||z.reason!==p.p_reason||z.staff_context.count!==p.p_expected_count||JSON.stringify(requested)!==JSON.stringify(p.p_lines)))fail();
 return s;
}
function workspace(s,owner,actor){
 R.identity(s,'cashier-partial-workspace-v1',owner,actor);
 if(typeof s.can_partial_refund!=='boolean'||!Array.isArray(s.documents))fail();
 R.workspace({...s,scope:'cashier-refund-workspace-v1',can_refund:s.can_partial_refund,refunds:s.documents.map(z=>({...z,reversal_no:z.return_no}))},owner,actor);return s;
}
root.StaffPartial={number:R.number,source,context,sameContext,preview,payload,pending,document,workspace,allocations};
if(typeof module==='object'&&module.exports)module.exports=root.StaffPartial;
})(globalThis);
