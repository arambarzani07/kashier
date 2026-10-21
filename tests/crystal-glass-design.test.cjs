'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const html=fs.readdirSync(root).filter(name=>name.endsWith('.html'));
const css=fs.readFileSync(path.join(root,'glass-system.css'),'utf8');
const pages=html.filter(name=>name!=='maintenance.html');
test('all 42 application pages share one Crystal Glass stylesheet and remain Sorani RTL',()=>{
 assert.equal(html.length,43,'HTML inventory changed: inspect new screens before release');
 assert.equal(pages.length,42);
 for(const name of pages){
  const page=fs.readFileSync(path.join(root,name),'utf8');
  const refs=page.match(/<link rel="stylesheet" href="glass-system\.css">/g)||[];
  assert.equal(refs.length,1,name+' must import shared design exactly once');
  assert.match(page,/<html[^>]*lang="ckb"[^>]*dir="rtl"/i,name+' must be Sorani RTL');
  const lastLink=page.lastIndexOf('<link rel="stylesheet" href="glass-system.css">');
  assert.ok(lastLink<page.search(/<\/head\s*>/i)&&lastLink>0,name+' theme must load inside head');
 }
});
test('maintenance must stay visually and operationally isolated',()=>{
 const maintenance=fs.readFileSync(path.join(root,'maintenance.html'),'utf8');
 const routing=fs.readFileSync(path.join(root,'vercel.json'),'utf8');
 assert.doesNotMatch(maintenance,/glass-system\.css/);
 assert.match(routing,/maintenance\\{2}\.html/);
 assert.match(routing,/release-check|maintenance\.html/);
});
test('design tokens cover typography, color, surfaces, radius, shadow and focus for all pages',()=>{
 for(const token of [
 '--kg-font','--kg-ink','--kg-primary','--kg-danger','--kg-success','--kg-warning',
 '--kg-canvas','--kg-glass-strong','--kg-glass-medium','--kg-glass-light',
 '--kg-stroke','--kg-radius-sm','--kg-radius-md','--kg-radius-lg','--kg-shadow-md','--kg-blur'
 ])assert.ok(css.includes(token),token+' missing');
 for(const item of ['.tile','.topbar','.cart-panel','.payment-panel','.home-summary',
   '.home-summary-grid a','.primary','.secondary','dialog','table','input','select','textarea',
   '.access-panel','.identity-panel'])assert.ok(css.includes(item),item+' missing');
});
test('glass appearance never changes receipt printing and respects reduced motion/transparency',()=>{
 assert.match(css,/@media screen\s*{/);
 assert.doesNotMatch(css,/@media print\s*{/);
 assert.match(css,/\.print-area/);
 assert.match(css,/prefers-reduced-motion: reduce/);
 assert.match(css,/prefers-reduced-transparency: reduce/);
 assert.match(css,/backdrop-filter: none/);
 assert.doesNotMatch(css,/background-attachment:\s*fixed/);
 assert.doesNotMatch(css,/!important[^;]*background/i);
});
test('visual theme contains no login privileges, financial operations, or network traffic',()=>{
 assert.doesNotMatch(css,/fetch\s*\(|localStorage|sessionStorage|service_role|owner_id|INSERT INTO/i);
});

test('v2 checkout refinement keeps totals and barcode usable at mobile sizes',()=>{
 const expected=[
  'body .sale-layout > * { min-width: 0; }',
  'body .cart-panel .table-wrap',
  'overflow-x: auto;',
  'body .scan-form input',
  'body .payment-panel .complete-sale',
  '@media (max-width: 760px)',
  '@media (max-width: 480px)',
  'font-variant-numeric: tabular-nums'
 ];
 for(const phrase of expected)assert.ok(css.includes(phrase),phrase+' missing');
 assert.doesNotMatch(css,/body\s+table\s*\{\s*min-width:\s*540px/);
});

test('product header links wrap rather than extending outside the RTL viewport',()=>{
 assert.match(css,/body \.topbar \.header-links \{[\s\S]*?flex-wrap: wrap/);
 assert.match(css,/body \.topbar \.header-links \{[\s\S]*?max-width: 100%/);
 assert.match(css,/body \.topbar \.header-links \{ flex: 1 1 100%; width: 100%; \}/);
});

test('v3: financial tables keep intentional local scroll without overflowing the RTL page',()=>{
 assert.match(css,/body\.returns-page \.returns-list \.table-wrap \{[\s\S]*?overflow-x: auto/);
 assert.match(css,/body\.returns-page \.returns-list \.table-wrap > table/);
 assert.match(css,/body\.returns-page \.returns-filter > \*/);
 assert.match(css,/@media \(min-width: 1181px\) and \(max-width: 1440px\)/);
 assert.match(css,/grid-template-columns: repeat\(4,minmax\(0,1fr\)\)/);
 assert.match(css,/body\.returns-page \.returns-filter-actions \{[\s\S]*?flex-wrap: wrap/);
});

test('v4 common glass components normalize modules without restyling printed media',()=>{
 for(const selector of [
 '.returns-filter','.returns-list','.cash-overview','.cash-totals article',
 '.debt-summary > div','.payable-summary > div','.price-search','.price-matches',
 '.labels-controls','.stocktake-controls','#count-sheet','.statement-controls',
 '.receipt-paper','.statement-paper','.return-panel','.reversal-panel',
 '.debt-delta-repayment','.payable-delta-payment','.field-error'
 ]) assert.ok(css.includes(selector),selector+' must share visual vocabulary');
 assert.match(css,/body dialog \{[\s\S]*?max-height: calc\(100dvh - 24px\)/);
 assert.match(css,/@media \(forced-colors: active\)/);
 assert.match(css,/\.receipt-paper, \.statement-paper, #purchase-report-paper/);
});
