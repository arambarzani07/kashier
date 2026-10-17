const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

test('returns page exposes type, Baghdad date, search and pagination controls',()=>{
 const html=fs.readFileSync(require.resolve('../returns.html'),'utf8');
 for(const id of ['returns-kind','returns-from','returns-to','returns-query','returns-rows','returns-previous','returns-next'])assert.match(html,new RegExp('id="'+id+'"'));
 assert.match(html,/گەڕاندنەوەی تەواو/);assert.match(html,/گەڕاندنەوەی بەشی/);assert.match(html,/بەروار بە پێی بغداد/);
});

test('returns UI links every row back to the immutable source receipt and avoids dynamic innerHTML',()=>{
 const js=fs.readFileSync(require.resolve('../returns.js'),'utf8');
 assert.match(js,/receipt\.html\?id=/);
 assert.doesNotMatch(js,/innerHTML\s*=/);
 assert.match(js,/textContent=/);
});

test('dashboard loads a dedicated returns tile that routes to the returns page',()=>{
 const html=fs.readFileSync(require.resolve('../index.html'),'utf8');
 const tile=fs.readFileSync(require.resolve('../returns-tile.js'),'utf8');
 assert.match(html,/returns-tile\.js/);assert.match(tile,/data-module|dataset\.module/);assert.match(tile,/returns\.html/);assert.match(tile,/گەڕاندنەوەکان/);
});
