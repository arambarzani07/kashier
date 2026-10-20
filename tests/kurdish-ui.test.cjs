const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
function setup(){const events={};const context={document:{addEventListener:(name,fn)=>events[name]=fn}};vm.runInNewContext(fs.readFileSync(require.resolve('../kurdish-ui.js'),'utf8'),context);return {locale:context.KashierLocale,events};}
test('browser validation uses Sorani and editing clears the prior custom error',()=>{
 const {locale,events}=setup();
 for(const flag of ['valueMissing','typeMismatch','tooShort','tooLong','rangeUnderflow','rangeOverflow','stepMismatch','badInput','patternMismatch']){
  const field={type:'text',validity:{[flag]:true,valid:false},setCustomValidity(v){this.message=v;}};
  events.invalid({target:field});assert.match(field.message,/[\u0600-\u06ff]/);assert.doesNotMatch(field.message,/[A-Za-z]/);
  events.input({target:field});assert.equal(field.message,'');
 }
 assert.equal(locale.validation({validity:{valid:true}}),'');
 assert.match(locale.validation({type:'checkbox',validity:{valueMissing:true}}),/هەڵبژێرە/);
 assert.match(locale.validation({type:'file',validity:{valueMissing:true}}),/فایل/);
});
test('technical exception prose has a Kurdish fallback while existing Sorani detail is retained',()=>{
 const {locale}=setup();for(const raw of ['Failed to fetch','Invalid draft',undefined])assert.match(locale.message(raw),/کردارەکە تەواو نەبوو/);
 assert.equal(locale.message('قەرزی کڕیار گۆڕاوە.'),'قەرزی کڕیار گۆڕاوە.');
});
test('Kurdish import headings preserve codes and money and retain legacy compatibility',()=>{
 const parser=require('../product-import-csv.js');
 const kurdish=parser.parse('ناو,بارکۆد,نرخی_فرۆشتن\nشیر,001234,1500');
 assert.deepEqual(kurdish,parser.parse('name,barcode,sale_price\nشیر,001234,1500'));
 assert.equal(kurdish[0].barcode,'001234');assert.equal(kurdish[0].sale_price,1500);
 assert.throws(()=>parser.parse('ناو,نرخی_فرۆشتن,بارکۆد\nشیر,1500,001234'));
});
test('static UI copy is Sorani and every operational page loads validation localization',()=>{
 const root=path.resolve(__dirname,'..');
 for(const name of fs.readdirSync(root).filter(n=>n.endsWith('.html'))){
  const html=fs.readFileSync(path.join(root,name),'utf8');
  const markup=html.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/g,'');
  const text=markup.replace(/<[^>]*>/g,'').replace(/&#?\w+;/g,'');
  assert.doesNotMatch(text,/[A-Za-z]/,name);
  if(!name.includes('preview')&&name!=='maintenance.html')assert.match(html,/src="kurdish-ui.js"/,name);
 }
});
