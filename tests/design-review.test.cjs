const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function setup({complete=false}={}){
 const events=()=>({events:{},addEventListener(k,f){this.events[k]=f;}});
 const screen={...events(),value:'design-preview.html',options:[{value:'design-preview.html',textContent:'Home'},{value:'sale-preview.html',textContent:'Sale'},{value:'products-preview.html',textContent:'Products'}]};
 const width={...events(),value:'1280'},status={textContent:''},reload=events(),form=events(),attrs={},navigations=[];
 let shown='https://kashier-hazel.vercel.app/design-preview.html',blocked=false;
 const frame={...events(),style:{},contentDocument:{readyState:complete?'complete':'loading'},setAttribute:(k,v)=>attrs[k]=v};
 Object.defineProperty(frame,'src',{set:v=>navigations.push(v)});
 Object.defineProperty(frame,'contentWindow',{get(){if(blocked)throw Error('cross origin');return {location:{href:shown}};}});
 const nodes={'#review-screen':screen,'#review-width':width,'#review-frame':frame,'#review-status':status,'#review-reload':reload,'#review-controls':form};
 vm.runInNewContext(fs.readFileSync(require.resolve('../design-review.js'),'utf8'),{document:{querySelector:k=>nodes[k]},URL,location:{origin:'https://kashier-hazel.vercel.app',href:'https://kashier-hazel.vercel.app/design-review.html'}});
 return {screen,width,frame,status,attrs,navigations,
  load(path){shown='https://kashier-hazel.vercel.app/'+path;blocked=false;frame.events.load();},
  select(value){screen.value=value;screen.events.change();},
  resize(value){width.value=value;width.events.change();},
  external(){blocked=true;frame.events.load();},
  retry(){reload.events.click();}};
}
test('initial loading remains busy until the preview actually loads',()=>{const x=setup();assert.equal(x.attrs['aria-busy'],'true');assert.equal(x.navigations.length,0);x.load('design-preview.html');assert.equal(x.attrs['aria-busy'],'false');assert.match(x.status.textContent,/Home.*1280.*بارکرا/);});
test('rapid selection ignores the previous preview load event',()=>{const x=setup();x.load('design-preview.html');x.select('sale-preview.html');x.select('products-preview.html');x.load('sale-preview.html');assert.equal(x.screen.value,'products-preview.html');assert.equal(x.attrs['aria-busy'],'true');x.load('products-preview.html');assert.equal(x.attrs['aria-busy'],'false');assert.match(x.status.textContent,/Products/);});
test('resizing during navigation does not reload or claim completion',()=>{const x=setup();x.load('design-preview.html');x.select('sale-preview.html');const count=x.navigations.length;x.resize('390');assert.equal(x.navigations.length,count);assert.equal(x.frame.style.width,'390px');assert.equal(x.attrs['aria-busy'],'true');assert.doesNotMatch(x.status.textContent,/بارکرا/);x.load('sale-preview.html');assert.match(x.status.textContent,/390/);});
test('links inside a loaded preview update the selected screen',()=>{const x=setup();x.load('design-preview.html');x.load('products-preview.html');assert.equal(x.screen.value,'products-preview.html');assert.match(x.frame.title,/Products/);});
test('unknown and inaccessible pages cannot be reported as a loaded preview',()=>{for(const external of [false,true]){const x=setup();x.load('design-preview.html');if(external)x.external();else x.load('auth.html');assert.doesNotMatch(x.status.textContent,/بارکرا/);x.resize('768');assert.doesNotMatch(x.status.textContent,/بارکرا/);x.retry();assert.equal(x.navigations.at(-1),'design-preview.html');x.load('design-preview.html');assert.match(x.status.textContent,/768.*بارکرا/);}});
test('unsupported selections are ignored and preloaded frames need no duplicate navigation',()=>{const x=setup({complete:true});assert.equal(x.navigations.length,0);assert.equal(x.attrs['aria-busy'],'false');x.select('https://example.com/');assert.equal(x.navigations.length,0);x.screen.value='design-preview.html';x.resize('99999');assert.equal(x.frame.width,1280);});
