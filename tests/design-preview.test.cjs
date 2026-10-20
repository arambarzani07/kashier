const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
test('public operational previews cannot load account scripts or submit business forms',()=>{
 for(const name of fs.readdirSync(root).filter(n=>n.endsWith('-preview.html')&&n!=='design-preview.html')){
  const html=fs.readFileSync(path.join(root,name),'utf8');
  assert.deepEqual([...html.matchAll(/<script\b[^>]*src="([^"]+)"/g)].map(m=>m[1]),['preferences.js']);
  for(const [tag] of html.matchAll(/<(?:input|button|select|textarea)\b[^>]*>/g))assert.match(tag,/\sdisabled(?:\s|>)/);
  assert.doesNotMatch(html,/\bon(?:click|submit|change|input)\s*=/i);
  assert.match(html,/screen-preview-bar/);
 }
 const sale=fs.readFileSync(path.join(root,'sale-preview.html'),'utf8');
 for(const id of ['subtotal','total','balance'])assert.match(sale,new RegExp(`id="${id}">—`));
 assert.match(fs.readFileSync(path.join(root,'employees-preview.html'),'utf8'),/دوای چوونەژوورەوە، لیستی کارمەندەکان/);
});
