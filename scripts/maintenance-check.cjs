#!/usr/bin/env node
'use strict';
// Maintenance-only release gate: refuses accidental application exposure.
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
function fail(message){console.error('MAINTENANCE BUILD BLOCKED: '+message);process.exit(1);}
const config=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));
if(config.framework!==null||config.outputDirectory!=='dist'||config.buildCommand!=='node scripts/release-check.cjs')fail('unexpected Vercel build/output config');
if(!Array.isArray(config.routes)||config.routes.length!==2||config.routes[1]?.handle!=='filesystem')fail('route inventory changed');
const [guard]=config.routes;
if(guard.dest!=='/maintenance.html'||guard.headers?.['Cache-Control']!=='no-store')fail('maintenance routing missing');
let expression;try{expression=new RegExp('^'+guard.src);}catch{fail('invalid maintenance route regex');}
for(const sample of ['/','/index.html','/auth.html','/sale.html','/staff.html','/config.js','/data.js','/api/example','/private/path']){
 if(!expression.test(sample))fail('path bypasses maintenance: '+sample);
}
if(expression.test('/maintenance.html'))fail('maintenance page recursively rewritten');
const source=path.join(root,'maintenance.html'),publicPage=path.join(root,'dist','maintenance.html');
if(!fs.existsSync(source)||!fs.existsSync(publicPage))fail('missing maintenance page');
const page=fs.readFileSync(publicPage,'utf8');
if(page!==fs.readFileSync(source,'utf8'))fail('maintenance output differs from source');
if(!page.includes('لە بازسازیدایە')||!page.includes('noindex,nofollow'))fail('maintenance text/meta missing');
if(/<(?:script|form|iframe|object|embed)\b/i.test(page)||/\b(?:src|href)\s*=\s*['\"]/i.test(page))fail('maintenance page must be standalone');
console.log('PASS: fail-closed maintenance build, safe rewrite coverage, static page parity, no interactive dependencies.');
