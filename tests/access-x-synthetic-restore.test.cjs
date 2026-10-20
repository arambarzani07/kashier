'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const shell=fs.readFileSync(path.join(root,'scripts/access-x-synthetic-restore.sh'),'utf8');
const fixture=fs.readFileSync(path.join(root,'tests/access-x-synthetic-fixture.sql'),'utf8');
const verify=fs.readFileSync(path.join(root,'tests/access-x-synthetic-verify.sql'),'utf8');
test('synthetic rehearsal refuses unapproved database or production credentials',()=>{
 assert.match(shell,/PGHOST" != "127\.0\.0\.1"/);
 assert.match(shell,/PGDATABASE" != "kashier_replay"/);
 assert.match(shell,/ACCESS_X_SYNTHETIC_DRILL" != "true"/);
 assert.match(shell,/createdb --template=template0 kashier_restore_check/);
 assert.match(shell,/pg_restore --exit-on-error --single-transaction/);
 assert.doesNotMatch(shell,/SUPABASE_(SERVICE_ROLE|DB_PASSWORD)|postgresql:\/\/|db\.[^.]+\.supabase\.co/);
 assert.doesNotMatch(shell,/upload-artifact|curl |wget /);
});
test('synthetic fixture uses actual financial RPCs and verifies balances and references',()=>{
 assert.match(fixture,/public\.post_cash_sale\(/);
 assert.match(fixture,/public\.post_debt_entry\(/);
 assert.match(fixture,/set local role authenticated/);
 assert.doesNotMatch(fixture,/insert into public\.(?:debt_entries|sales|cash_movements)/i);
 assert.match(verify,/v_balance<>16000/);
 assert.match(verify,/v_balance<>11500/);
 assert.match(verify,/v_balance<>14000/);
});
