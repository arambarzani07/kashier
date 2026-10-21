'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const read=name=>fs.readFileSync(path.join(root,name),'utf8');
const pages=fs.readdirSync(root).filter(name=>name.endsWith('.html'));

test('every interactive screen uses the shared theme before device accessibility preferences',()=>{
 for(const name of pages.filter(name=>name!=='maintenance.html')){
  const html=read(name);
  const css=[...html.matchAll(/<link\b[^>]*href="([^"]+\.css)"/g)].map(m=>m[1]);
  assert.equal(css.filter(x=>x==='design-system.css').length,1,name);
  assert.deepEqual(css.slice(-2),['design-system.css','preferences.css'],name);
  assert.match(html,/<body\b[^>]*class="[^"]*\bkashier-ui\b/,name);
  assert.match(html,/<header\b[^>]*class="[^"]*\btopbar\b/,name);
  assert.match(html,/<html lang="ckb" dir="rtl">/,name);
 }
});

test('standalone maintenance output shares canonical tokens without loading app assets',()=>{
 const tokens=read('design-system.css').match(/:root \{[\s\S]*?\n\}/)[0];
 assert.ok(read('maintenance.html').includes(tokens));
 assert.equal(read('maintenance.html'),read('dist/maintenance.html'));
 assert.doesNotMatch(read('maintenance.html'),/<(?:script|link|form)\b/i);
});

test('theme is screen-scoped and leaves print templates to their feature stylesheets',()=>{
 const css=read('design-system.css');
 const screen=css.indexOf('@media screen');
 assert.ok(screen>0);
 assert.doesNotMatch(css.slice(0,screen),/(?:^|[;{]\s*)(?:width|height|padding|margin)\s*:/);
 assert.doesNotMatch(css,/@page|@media print|localStorage|url\(/);
});
