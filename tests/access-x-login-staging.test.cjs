'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const vercel=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));
test('new login core is inert under the maintenance-only Vercel route contract',()=>{
 const route=vercel.routes?.[0];
 assert.equal(route?.dest,'/maintenance.html');
 assert.equal(vercel.buildCommand,'node scripts/release-check.cjs');
 assert.equal(vercel.outputDirectory,'dist');
 assert.match('/api/access-x/login',new RegExp('^'+route.src));
 assert.equal(fs.existsSync(path.join(root,'api','access-x','login.js')),false);
 assert.equal(fs.existsSync(path.join(root,'dist','access-x','login-core.cjs')),false);
 assert.equal(fs.existsSync(path.join(root,'dist','api','access-x','login.js')),false);
});