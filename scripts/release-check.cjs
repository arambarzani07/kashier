#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname,'..');
function run(args) {
  const result = spawnSync(process.execPath,args,{cwd:root,stdio:'inherit'});
  if (result.error) console.error(result.error.message);
  if (result.error || result.status !== 0) process.exit(result.status || 1);
}
run(['scripts/verify-static-assets.cjs']);
const tests = fs.readdirSync(path.join(root,'tests'))
  .filter(file=>file.endsWith('.test.cjs')).sort().map(file=>'tests/'+file);
if (!tests.length) {
  console.error('Release blocked: no regression test files found.');
  process.exit(1);
}
run(['--test','--test-reporter=dot',...tests]);
console.log(`Release verification passed: ${tests.length} regression test files and all static assets.`);
