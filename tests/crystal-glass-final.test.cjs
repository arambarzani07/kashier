'use strict';
// Regression contract for the draft Crystal Glass UI branch.
// All checks operate on source assets only, never real user / financial data.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const css=fs.readFileSync(path.join(root,'glass-system.css'),'utf8');
test('Crystal Glass remains screen-only and avoids fixed-position background repainting',()=>{
 assert.match(css,/\/\* Crystal Glass final polish/);
 assert.match(css,/@media screen\s*\{/);
 assert.doesNotMatch(css,/@media print|@page|background-attachment:fixed/);
 assert.match(css,/background-attachment:scroll/);
});
test('one set of cards, controls, table wrappers and RTL navigation shapes',()=>{
 for(const term of ['--glass-radius','--glass-control-radius','.cart-panel','.payment-panel','.desk-catalog',
  '.returns-list','.label-queue-panel','.home-summary','.table-wrap','.count-table-wrap',
  '.primary','.secondary','.complete-sale','.header-links','.sale-header-nav','.desk-nav']){
  assert.ok(css.includes(term),'missing '+term);
 }
 assert.match(css,/overflow-x:auto/);
 assert.match(css,/overscroll-behavior-inline:contain/);
 assert.match(css,/font-variant-numeric:tabular-nums/);
 assert.match(css,/html body\.kashier-ui dialog \{[\s\S]*?max-height:calc\(100dvh - 24px\)/);
});
test('receipts, statements, reports and shelf labels stay opaque paper in glass UI',()=>{
 for(const term of ['.receipt-paper','.statement-paper','.return-document-paper',
  '#purchase-report-paper','#expense-paper','#label-preview','.product-label'])
  assert.ok(css.includes(term),'paper missing '+term);
 assert.match(css,/background:#fff!important/);
 assert.match(css,/backdrop-filter:none!important/);
});
test('glass uses accessible system alternatives and CSS-only behavior',()=>{
 assert.match(css,/prefers-reduced-transparency:reduce/);
 assert.match(css,/forced-colors:active/);
 assert.match(css,/prefers-reduced-motion:reduce/);
 assert.doesNotMatch(css,/fetch\s*\(|localStorage|sessionStorage|service_role|INSERT INTO/i);
});
