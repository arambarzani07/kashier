'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const config=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));
test('Vercel fail-closed maintenance routing cannot expose old login or staff routes',()=>{
 assert.equal(config.buildCommand,'node scripts/release-check.cjs');
 assert.equal(config.outputDirectory,'dist');
 assert.equal(config.routes.length,2);
 assert.equal(config.routes[0].dest,'/maintenance.html');
 assert.equal(config.routes[0].headers['Cache-Control'],'no-store');
 assert.equal(config.routes[1].handle,'filesystem');
 const matcher=new RegExp('^'+config.routes[0].src);
 for(const url of ['/','/index.html','/auth.html','/sale.html','/cashier.html','/staff.html','/config.js','/data.js','/maintenance.html/anything'])assert.equal(matcher.test(url),true,url);
 assert.equal(matcher.test('/maintenance.html'),false);
});
test('maintenance build validates self-contained exact deployment page',()=>{
 const result=spawnSync(process.execPath,['scripts/release-check.cjs'],{cwd:root,encoding:'utf8'});
 assert.equal(result.status,0,result.stderr||result.stdout);
 assert.equal(fs.readFileSync(path.join(root,'maintenance.html'),'utf8'),fs.readFileSync(path.join(root,'dist/maintenance.html'),'utf8'));
 assert.match(result.stdout,/fail-closed maintenance build/);
});
