'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
test('2026-10-20 applied migration inventory is preserved byte-for-byte by filenames',()=>{
 const baseline=fs.readFileSync(path.join(root,'supabase/applied-migrations-20261020.txt'),'utf8').trim().split(/\r?\n/);
 const stored=fs.readdirSync(path.join(root,'supabase/migrations')).filter(x=>x.endsWith('.sql')).sort();
 assert.equal(baseline.length,72);
 assert.deepEqual([...baseline].sort(),stored);
 for(const file of stored)assert.match(file,/^\d{14}_[a-z0-9_]+\.sql$/);
});
