const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

test('quick return page is scanner-first and exposes only explicit return actions',()=>{
 const html=fs.readFileSync(require.resolve('../quick-return.html'),'utf8');
 for(const id of ['quick-return-form','receipt-code','quick-return-status','quick-return-result','open-receipt','partial-return-action','full-return-action','return-document-action'])assert.match(html,new RegExp('id="'+id+'"'));
 assert.match(html,/K-123/);assert.match(html,/autofocus/);assert.match(html,/return-lookup-data\.js/);assert.match(html,/quick-return\.js/);
});

test('quick return UI reads real reversal state and never injects dynamic innerHTML',()=>{
 const js=fs.readFileSync(require.resolve('../quick-return.js'),'utf8');
 assert.match(js,/getSaleReversal/);assert.match(js,/listSaleReturns/);
 assert.match(js,/#partial-return-panel/);assert.match(js,/#reversal-panel/);
 assert.match(js,/payment_mode==='cash'/);assert.match(js,/discount/);
 assert.doesNotMatch(js,/innerHTML\s*=/);
});

test('discounted cash receipts keep partial return available while credit partial remains locked',()=>{
 const js=fs.readFileSync(require.resolve('../quick-return.js'),'utf8');
 assert.match(js,/if\(sale\.payment_mode==='cash'\)\{partial\.href=receiptHref/);
 assert.match(js,/net allocation/);
 assert.match(js,/Partial Return ـی credit هێشتا قوفڵە/);
 assert.doesNotMatch(js,/لەبەر داشکاندن، Partial Return ـی زیاتر هێشتا قوفڵە/);
 assert.doesNotMatch(js,/Partial Return تا allocation ـی دقیق داشکاندن قوفڵە/);
});

test('dashboard loads a dedicated quick return tile',()=>{
 const html=fs.readFileSync(require.resolve('../index.html'),'utf8');
 const tile=fs.readFileSync(require.resolve('../quick-return-tile.js'),'utf8');
 assert.match(html,/quick-return-tile\.js/);assert.match(tile,/quick-return\.html/);assert.match(tile,/گەڕاندنەوەی خێرا/);assert.match(tile,/quick-return/);
});

test('sale receipts load local CODE128 renderer and print a K-prefixed receipt code',()=>{
 const html=fs.readFileSync(require.resolve('../receipt.html'),'utf8');
 const js=fs.readFileSync(require.resolve('../receipt-barcode.js'),'utf8');
 assert.match(html,/vendor\/JsBarcode\.all\.min\.js/);assert.match(html,/receipt-barcode\.js/);assert.match(html,/receipt-barcode\.css/);
 assert.match(js,/CODE128/);assert.match(js,/K-\[0-9\]\+/);assert.match(js,/JsBarcode/);assert.match(js,/receipt-scan-code/);
});
