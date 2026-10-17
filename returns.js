'use strict';
const $=selector=>document.querySelector(selector);
const state={page:0,limit:50,total:0,loading:false};
const formatMoney=value=>new Intl.NumberFormat('en-US').format(Number(value||0))+' دینار';
const formatDate=value=>new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'short'}).format(new Date(value));
function cell(text,cls=''){const node=document.createElement('td');node.textContent=text??'';if(cls)node.className=cls;return node;}
function currentFilters(){return {kind:$('#returns-kind').value,from:$('#returns-from').value||null,to:$('#returns-to').value||null,query:$('#returns-query').value.trim(),page:state.page,limit:state.limit};}
function validateDates(){const from=$('#returns-from').value,to=$('#returns-to').value;if(from&&to&&from>to)throw new Error('بەرواری سەرەتا نابێت دوای بەرواری کۆتایی بێت.');}
function render(rows){const body=$('#returns-rows');body.replaceChildren();for(const item of rows){const row=document.createElement('tr');const prefix=item.kind==='full'?'R-':'PR-';row.append(cell(prefix+item.return_no,'returns-code'),cell(formatDate(item.created_at),'returns-date'));
 const kindCell=document.createElement('td'),badge=document.createElement('span');badge.className='returns-kind '+item.kind;badge.textContent=item.kind==='full'?'تەواو':'بەشی';kindCell.append(badge);row.append(kindCell);
 row.append(cell('K-'+item.receipt_no,'returns-source'),cell(item.customer_name||'—','returns-customer'),cell(formatMoney(item.total),'returns-money'),cell(formatMoney(item.cash_refund),'returns-money'),cell(formatMoney(item.debt_reversed),'returns-money'),cell(item.reason,'returns-reason'));
 const action=document.createElement('td'),link=document.createElement('a');link.className='returns-action';link.href='receipt.html?id='+encodeURIComponent(item.sale_id);link.textContent='کردنەوەی پسوولە';action.append(link);row.append(action);body.append(row);}
 $('#returns-empty').hidden=rows.length!==0;
}
function updatePaging(){const pages=Math.max(1,Math.ceil(state.total/state.limit)),start=state.total?state.page*state.limit+1:0,end=Math.min(state.total,(state.page+1)*state.limit);$('#returns-total').textContent=new Intl.NumberFormat('en-US').format(state.total);$('#returns-page-label').textContent=(state.page+1)+' / '+pages;$('#returns-count').textContent=state.total?start+'–'+end+' لە '+state.total:'0';$('#returns-previous').disabled=state.loading||state.page===0;$('#returns-next').disabled=state.loading||(state.page+1)*state.limit>=state.total;}
async function load(){if(state.loading)return;if(!KashierData.loggedIn()){location.replace('auth.html?next='+encodeURIComponent('returns.html'));return;}try{validateDates();}catch(e){$('#returns-status').textContent=e.message;return;}state.loading=true;$('#returns-status').textContent='تۆمارەکان دەخوێندرێنەوە…';$('#returns-refresh').disabled=true;updatePaging();try{const result=await KashierReturns.list(currentFilters());state.total=result.total;if(state.page>0&&result.rows.length===0&&state.total>0){state.page=Math.max(0,Math.ceil(state.total/state.limit)-1);return await loadAfterUnlock();}render(result.rows);$('#returns-status').textContent=result.rows.length?'':'هیچ تۆمارێک بەم فلتەرە نییە.';}catch(e){render([]);$('#returns-status').textContent=e.message;if(e.status===401)setTimeout(()=>location.replace('auth.html?next='+encodeURIComponent('returns.html')),0);}finally{state.loading=false;$('#returns-refresh').disabled=false;updatePaging();}}
async function loadAfterUnlock(){state.loading=false;return load();}
$('#returns-filter').addEventListener('submit',event=>{event.preventDefault();state.page=0;load();});
$('#returns-clear').addEventListener('click',()=>{$('#returns-kind').value='all';$('#returns-from').value='';$('#returns-to').value='';$('#returns-query').value='';state.page=0;load();});
$('#returns-refresh').addEventListener('click',load);
$('#returns-previous').addEventListener('click',()=>{if(state.page>0){state.page--;load();}});
$('#returns-next').addEventListener('click',()=>{if((state.page+1)*state.limit<state.total){state.page++;load();}});
load();
