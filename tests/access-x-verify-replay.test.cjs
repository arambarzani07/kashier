'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {tokenize,canonical,verifyReport}=require('../scripts/access-x-verify-replay.cjs');
const root=path.resolve(__dirname,'..');
const baseline=JSON.parse(fs.readFileSync(path.join(root,'tests/access-x-function-tokens-20261020.json'),'utf8'));
const defs=fs.readFileSync(path.join(root,'tests/access-x-object-definitions-20261020.txt'),'utf8');
const rights=fs.readFileSync(path.join(root,'tests/access-x-semantic-rights-20261020.txt'),'utf8');
test('exactly seven verified SQL function definitions are pinned',()=>{
 assert.equal(Object.keys(baseline).length,7);
 for(const tokens of Object.values(baseline))assert.ok(tokens.length>180);
 assert.equal(defs.trim().split('\n').length,214);
 assert.equal(rights.trim().split('\n').length,221);
});
test('tokenization ignores formatting but preserves SQL quoted strings and operators',()=>{
 assert.deepEqual(tokenize("select a->>'id' -- comment\n from t"),tokenize("select  a ->> 'id' from t"));
 assert.notDeepEqual(tokenize("select 'a b'"),tokenize("select 'ab'"));
 assert.notDeepEqual(tokenize("select a::bigint"),tokenize("select a::text"));
 assert.notDeepEqual(tokenize("select 'abc'"),tokenize("select 'abd'"));
 assert.throws(()=>tokenize("select 'unclosed"));
});
test('optional AS normalization is limited to the two reviewed cash statement aliases',()=>{
 const before=tokenize("select coalesce(a,b) as purchase_id,coalesce(x,y) as linked_sale_id");
 const after=tokenize("select coalesce(a,b) purchase_id,coalesce(x,y) linked_sale_id");
 assert.deepEqual(canonical('public.get_cash_statement',before),canonical('public.get_cash_statement',after));
 assert.notDeepEqual(canonical('public.another_report',before),canonical('public.another_report',after));
 assert.notDeepEqual(canonical('public.get_cash_statement',tokenize("select sum(a) as total")),canonical('public.get_cash_statement',tokenize("select sum(a) total")));
});
test('parity verifier refuses missing, duplicate or unexpected replay metadata',()=>{
 assert.throws(()=>verifyReport('',defs,rights,baseline),/effective grants|policy targets/);
 const duplicate=rights.trim()+'\n'+rights.trim().split('\n')[0];
 assert.throws(()=>verifyReport(duplicate,defs,rights,baseline),/Duplicate/);
 assert.throws(()=>verifyReport(rights.trim(),defs,rights,baseline),/schema object definition/);
});
