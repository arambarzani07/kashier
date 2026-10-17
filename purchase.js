'use strict';
const $ = selector => document.querySelector(selector);
const purchaseOwner=KashierData.userId(),key = 'kashier.purchase-draft.v1.' + (purchaseOwner || 'local');
const format = value => new Intl.NumberFormat('en-US').format(value);
let selectedSupplier=null,supplierRequest=0;
const tracked=()=>$('#purchase-accounting').value==='tracked';
function validFinance(){if(!tracked())return true;try{return Boolean(selectedSupplier&&/^[0-9a-f-]{36}$/i.test(selectedSupplier.id)&&total!==null&&SaleMath.money($('#purchase-paid').value)<=total);}catch{return false;}}
let items = [], posting = null, busy = false, total = 0, searchNumber = 0;
function node(tag, text) { const element = document.createElement(tag); if (text !== undefined) element.textContent = text; return element; }
function status(selector, text) { $(selector).textContent = text; $(selector).hidden = !text; }
function save() {
  try { sessionStorage.setItem(key, JSON.stringify({ version: 1, items, posting, accounting:tracked()?'tracked':'untracked',selectedSupplier,paid:$('#purchase-paid').value,supplier: $('#supplier').value, invoice: $('#invoice').value, note: $('#purchase-note').value })); return true; }
  catch { status('#purchase-post-status', 'مسودەکە نەپارێزرا؛ تۆمارکردن بەبێ پاراستنی ناسنامەی مامەڵە ئەنجام نادرێت.'); return false; }
}
function controls() {
  const locked = Boolean(posting);
  $('#legacy-supplier').hidden=tracked();$('#purchase-supplier').hidden=!tracked();$('#selected-supplier').textContent=selectedSupplier?'دابینکەر: '+selectedSupplier.name:'';$('#supplier-clear').hidden=!selectedSupplier;
  if(tracked()){try{const paid=SaleMath.money($('#purchase-paid').value);$('#purchase-debt').textContent=total!==null&&paid<=total?format(total-paid):'—';status('#purchase-finance-status',paid>total?'پارەی دراو لە کۆی کڕین زیاترە.':!selectedSupplier?'دابینکەرێکی تۆمارکراو هەڵبژێرە.':'');}catch(error){$('#purchase-debt').textContent='—';status('#purchase-finance-status',error.message);}}

  for (const input of document.querySelectorAll('[data-lock]')) input.disabled = locked;
  document.body.classList.toggle('posting', locked);
  $('#post-purchase').disabled = busy || (!locked && (!KashierData.loggedIn() || !items.length || total === null || !validFinance() || items.some(item => item.price < 1)));
  $('#post-purchase').textContent = busy ? 'تۆمارکردن…' : locked ? 'پشکنینەوەی هەمان کڕین' : 'تۆمارکردنی کڕین';
  $('#purchase-help').textContent = locked ? 'دۆخی کڕین هێشتا پشتڕاست نییە. هەمان داواکاری دووبارە دەنێردرێتەوە، بەبێ زیادکردنی دووبارەی کۆگا.' : tracked()?'کۆگا، پارەی دراو و قەرزی ماوە پێکەوە تۆمار دەکرێن.':'ئەم شێوازە تەنها کۆگا زیاد دەکات؛ پارەدان و قەرز تۆمار ناکات.';
}
function render() {
  $('#purchase-rows').replaceChildren();
  items.forEach((item, index) => {
    const row = node('tr'), name = node('td'); name.append(node('strong', item.name)); if (item.barcode) name.append(node('small', item.barcode)); row.append(name);
    for (const kind of ['quantity', 'price']) {
      const cell = node('td'), input = node('input'); input.type = 'number'; input.min = kind === 'quantity' ? '0.001' : '1'; input.max = kind === 'quantity' ? '10000' : '1000000000'; input.step = kind === 'quantity' ? '0.001' : '1'; input.value = kind === 'quantity' ? item.quantityUnits / 1000 : item.price || ''; input.inputMode = kind === 'quantity' ? 'decimal' : 'numeric'; input.setAttribute('data-lock', ''); input.setAttribute('aria-label', (kind === 'quantity' ? 'بڕی ' : 'نرخی کڕینی ') + item.name);
      input.addEventListener('change', () => {
        if (posting) return;
        try { if (!input.checkValidity()) throw new Error('بڕ یان نرخی کڕین نادروستە.'); const value = kind === 'quantity' ? SaleMath.quantityUnits(input.value) : SaleMath.money(input.value, 1000000000); if (kind === 'price' && value < 1) throw new Error('نرخی کڕین دەبێت زیاتر لە سفر بێت.'); items[index] = { ...item, [kind === 'quantity' ? 'quantityUnits' : 'price']: value }; status('#purchase-status', ''); render(); }
        catch (error) { status('#purchase-status', error.message); input.value = kind === 'quantity' ? item.quantityUnits / 1000 : item.price || ''; }
      }); cell.append(input); row.append(cell);
    }
    row.append(node('td', format(SaleMath.lineTotal(item)))); const action = node('td'), remove = node('button', '×'); remove.className = 'delete-item'; remove.setAttribute('data-lock', ''); remove.setAttribute('aria-label', 'سڕینەوەی ' + item.name); remove.addEventListener('click', () => { if (!posting) { items.splice(index, 1); render(); } }); action.append(remove); row.append(action); $('#purchase-rows').append(row);
  });
  try { total = SaleMath.totals(items, 0, 0).subtotal; } catch (error) { total = null; status('#purchase-status', error.message); }
  $('#purchase-total').textContent = total === null ? '—' : format(total); $('#purchase-count').textContent = format(items.length) + ' کاڵا'; $('#purchase-empty').hidden = items.length > 0; save(); controls();
}
function add(product) {
  if (posting||!KashierData.loggedIn()||KashierData.userId()!==purchaseOwner) return;
  try { const index = items.findIndex(item => item.productId === product.id); if (index >= 0) items[index].quantityUnits = SaleMath.quantityUnits((items[index].quantityUnits + 1000) / 1000); else { if (items.length >= 200) throw new Error('سنووری کڕین ٢٠٠ ڕیزە.'); items.push({ productId: product.id, name: product.name, barcode: product.barcode || '', quantityUnits: 1000, price: 0 }); } searchNumber++;$('#purchase-results').replaceChildren(); $('#purchase-query').value = ''; status('#purchase-status', 'نرخی کڕینی یەکە بنووسە.'); render(); }
  catch (error) { status('#purchase-status', error.message); }
}
$('#purchase-search').addEventListener('submit', async event => {
  event.preventDefault(); if (posting) return; const query = $('#purchase-query').value.trim(), request = ++searchNumber; $('#purchase-results').replaceChildren(); if (!query) return;
  if (!KashierData.loggedIn()) { location.href = 'auth.html?next=purchase.html'; return; }
  status('#purchase-status', 'گەڕان لە کاڵاکان…');
  try { const rows = await KashierData.lookupProducts(query); if (request !== searchNumber || posting || $('#purchase-query').value.trim() !== query) return; if(KashierData.userId()!==purchaseOwner)throw Error('هەژمارەکە گۆڕاوە؛ لە هەژماری سەرەتای کڕین بەردەوام بە.');const match=CatalogLookup.match(rows,query);if (match.exact) { add(match.exact); return; } status('#purchase-status', rows.length ? 'ئەنجامی گەڕان — بارکۆدی تەواو یەک ناگرێتەوە؛ کاڵاکە هەڵبژێرە:' : 'کاڵاکە نەدۆزرایەوە؛ سەرەتا کاڵای نوێ بناسێنە.'); for (const product of rows) { const button = node('button', product.name+' · '+(product.barcode||'بارکۆد نییە')); button.type = 'button'; button.addEventListener('click', () => {if(request===searchNumber&&$('#purchase-query').value.trim()===query)add(product);}); $('#purchase-results').append(button); } }
  catch (error) { if (request === searchNumber) status('#purchase-status', error.message); }
});
$('#purchase-query').addEventListener('input', () => { searchNumber++; $('#purchase-results').replaceChildren(); });
for (const selector of ['#supplier', '#invoice', '#purchase-note']) $(selector).addEventListener('input', save);
$('#clear-purchase').addEventListener('click', () => { if (!posting) $('#purchase-clear-dialog').showModal(); });
$('#cancel-purchase-clear').addEventListener('click', () => $('#purchase-clear-dialog').close());
$('#confirm-purchase-clear').addEventListener('click', () => { if (posting) return; items = [];selectedSupplier=null;$('#purchase-paid').value='0'; for (const selector of ['#supplier', '#invoice', '#purchase-note', '#purchase-query']) $(selector).value = ''; status('#purchase-status', ''); status('#purchase-post-status', ''); $('#purchase-clear-dialog').close(); render(); });
$('#post-purchase').addEventListener('click', async () => {
  if (busy) return;
  if(KashierData.userId()!==purchaseOwner){status('#purchase-post-status','هەژمارەکە گۆڕاوە؛ لە هەژماری سەرەتای کڕین بەردەوام بە.');return;}
  if (!posting) {
    if (!KashierData.loggedIn() || !items.length || total === null || !validFinance() || items.some(item => item.price < 1)) return;
    const id = crypto.randomUUID(); posting = { id, accounting:tracked()?'tracked':'untracked', payload: { p_id: id, p_items: items.map(item => ({ product_id: item.productId, quantity_units: item.quantityUnits, unit_cost: item.price })), p_supplier: tracked()?selectedSupplier.id:$('#supplier').value.trim(),...(tracked()?{p_paid:SaleMath.money($('#purchase-paid').value)}:{}), p_invoice: $('#invoice').value.trim(), p_note: $('#purchase-note').value.trim() } };
    if (!save()) { posting = null; controls(); return; }
  }
  busy = true; searchNumber++;supplierRequest++; $('#purchase-results').replaceChildren(); controls(); status('#purchase-post-status', 'تۆمارکردنی کڕین…');
  try { const receipt = await (posting.accounting==='tracked'?KashierData.postSupplierPurchase(posting.payload):KashierData.postPurchase(posting.payload)); if(KashierData.userId()!==purchaseOwner)throw Error('هەژمارەکە گۆڕاوە.');if (receipt?.id !== posting.id) throw new Error('وەڵامی کڕین پشتڕاست نەکرایەوە.'); try { sessionStorage.removeItem(key); } catch {} location.href = 'purchase-receipt.html?id=' + receipt.id + '&print=1'; }
  catch (error) { if ([400, 401, 403, 422].includes(error.status) && error.saleCode !== 'purchase_request_conflict') { posting = null; render(); status('#purchase-post-status', error.message); } else { save(); status('#purchase-post-status', 'دۆخی کڕین هێشتا پشتڕاست نییە؛ هەمان کڕین دووبارە بپشکنەوە.'); } }
  finally { busy = false; controls(); }
});
try {
  const draft = JSON.parse(sessionStorage.getItem(key) || 'null');
  if (draft) {
    if (draft.version !== 1 || !Array.isArray(draft.items) || draft.items.length > 200) throw new Error('Invalid draft');
    for (const item of draft.items) { if (!/^[0-9a-f-]{36}$/i.test(item.productId) || typeof item.name !== 'string' || !item.name.trim() || item.name.length > 150 || typeof item.barcode !== 'string' || item.barcode.length > 64 || !Number.isInteger(item.quantityUnits) || SaleMath.quantityUnits(item.quantityUnits / 1000) !== item.quantityUnits) throw new Error('Invalid item'); SaleMath.money(item.price, 1000000000); }
    $('#purchase-accounting').value=draft.accounting==='tracked'?'tracked':'untracked';if(draft.selectedSupplier&&/^[0-9a-f-]{36}$/i.test(draft.selectedSupplier.id)&&typeof draft.selectedSupplier.name==='string')selectedSupplier=draft.selectedSupplier;if(typeof draft.paid==='string')$('#purchase-paid').value=draft.paid;
    items = draft.items; if (draft.posting && draft.posting.payload?.p_id === draft.posting.id && /^[0-9a-f-]{36}$/i.test(draft.posting.id)) posting = draft.posting;
    $('#supplier').value = typeof draft.supplier === 'string' ? draft.supplier : ''; $('#invoice').value = typeof draft.invoice === 'string' ? draft.invoice : ''; $('#purchase-note').value = typeof draft.note === 'string' ? draft.note : '';
  }
} catch { status('#purchase-status', 'مسودەی پێشوو نەخوێندرایەوە؛ مسودەیەکی نوێ دەست پێ بکە.'); }
if (!KashierData.loggedIn()) location.replace('auth.html?next=purchase.html');
render();

$('#purchase-accounting').addEventListener('change',()=>{if(posting)return;supplierRequest++;$('#supplier-results').replaceChildren();save();controls();});
$('#purchase-paid').addEventListener('input',()=>{if(posting)return;save();controls();});
$('#supplier-query').addEventListener('input',()=>{supplierRequest++;$('#supplier-results').replaceChildren();});
$('#supplier-clear').addEventListener('click',()=>{if(posting)return;selectedSupplier=null;save();controls();});
$('#supplier-search-form').addEventListener('submit',async event=>{event.preventDefault();if(posting||!tracked())return;const query=$('#supplier-query').value.trim(),request=++supplierRequest;$('#supplier-results').replaceChildren();if(!query){status('#supplier-search-status','ناو یان تەلەفۆنی دابینکەر بنووسە.');return;}status('#supplier-search-status','گەڕان بۆ دابینکەر…');try{const {rows,total:count}=await KashierData.listSuppliers(query);if(request!==supplierRequest||posting||!tracked())return;status('#supplier-search-status',rows.length?(count>50?'یەکەم ٥٠ ئەنجام؛ گەڕانەکە وردتر بکە.':'دابینکەر هەڵبژێرە:'):'هیچ دابینکەرێک نەدۆزرایەوە.');for(const supplier of rows){const button=node('button',supplier.name+' · '+(supplier.phone||'')+' · قەرز: '+format(supplier.balance));button.type='button';button.setAttribute('data-lock','');button.addEventListener('click',()=>{if(posting)return;selectedSupplier={id:supplier.id,name:supplier.name};supplierRequest++;$('#supplier-results').replaceChildren();status('#supplier-search-status','');save();controls();});$('#supplier-results').append(button);}}catch(error){if(request===supplierRequest)status('#supplier-search-status',error.message);}});
