const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const pages=fs.readdirSync(root).filter(n=>n.endsWith('.html'));
test('every source and generated screen loads the final design contract exactly once',()=>{
 for(const file of pages){
  const html=fs.readFileSync(path.join(root,file),'utf8');
  assert.match(html,/<body\b[^>]*data-design="unified"/,file);
  const css=[...html.matchAll(/<link\b[^>]*rel="stylesheet"[^>]*href="([^"]+)"/g)].map(m=>m[1]);
  if(file==='maintenance.html'){
   assert.ok(html.includes('<style id="unified-design-inline">'+fs.readFileSync(path.join(root,'unified-design.css'),'utf8')+'</style>'));
   continue;
  }
  assert.equal(css.filter(s=>s==='unified-design.css').length,1,file);
  if (!file.startsWith('maintenance')) {
   assert.deepEqual(css.slice(-3),['design-system.css','glass-system.css','preferences.css'],file);
   assert.match(html,/class="[^"]*kashier-ui/,file);
  }
 }
});
test('every operational page has an isolated preview registered in the review selector',()=>{
 const review=fs.readFileSync(path.join(root,'design-review.html'),'utf8');
 const targets=[...review.matchAll(/<option value="([^"]+\.html)">/g)].map(m=>m[1]);
 const previews=pages.filter(n=>n.endsWith('-preview.html'));
 assert.equal(targets.length,previews.length);
 assert.equal(new Set(targets).size,targets.length);
 for(const target of previews)assert.ok(targets.includes(target),target);
 assert.equal(pages.filter(n=>!n.includes('preview')&&n!=='design-review.html').length,previews.length);
});
test('unified screen styling cannot change receipt or report print geometry',()=>{
 const css=fs.readFileSync(path.join(root,'unified-design.css'),'utf8');
 assert.match(css,/^\/\*[^]*?\*\/\s*@media screen\s*\{/);
 assert.doesNotMatch(css,/@media print|@page|!important[^]*?@media screen/);
 let depth=0,closed=false;
 for(const char of css.slice(css.indexOf('{'))){if(char==='{')depth++;if(char==='}'&&--depth===0)closed=true;else if(closed)assert.ok(/\s/.test(char));}
 assert.equal(depth,0);
});
