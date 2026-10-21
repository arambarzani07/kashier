#!/usr/bin/env node
'use strict';
// Offline browser layout QA: original application JS is stripped, fake examples only.
// No production URL, credentials, real records, or external HTTP requests are used.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),out=path.resolve(process.env.CRYSTAL_SCREENSHOT_DIR||'visual-qa-output');
const screens=fs.readdirSync(root).filter(name=>name.endsWith('.html')&&name!=='maintenance.html').sort();
// Every live app screen, including print-oriented/source-only views. Original JS is deliberately disabled.
assert.equal(screens.length,42,'page inventory changed; review the added/removed screens');
const sizes=[{name:'desktop-1366',width:1366,height:768},{name:'phone-390',width:390,height:844}];
function serverResponse(req,res){
 let name;
 try{ name=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname).replace(/^\/+/,'')||'index.html';
 if(!/^[\w.-]+$/.test(name)||name.includes('..'))throw Error('path'); }catch{res.writeHead(403);res.end();return;}
 const file=path.join(root,name);
 if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
 let s=fs.readFileSync(file,'utf8');
 if(name.endsWith('.html'))s=s.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi,'');
 res.writeHead(200,{'Content-Type':name.endsWith('.css')?'text/css':name.endsWith('.html')?'text/html':'text/plain',
  'Cache-Control':'no-store',
  'Content-Security-Policy':"default-src 'self'; script-src 'none'; connect-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; form-action 'none'; base-uri 'none'; frame-src 'none'"});
 res.end(s);
}
async function fixtures(page){
 // These DOM-only labels are fictional placeholders for visual QA; no backend activity.
 await page.evaluate(()=>{
  const tiles=document.getElementById('tiles');
  if(tiles){
   const labels=['کاڵاکان','فرۆشتن','کڕیاران','قەرز','قاسە','کۆگا','ڕاپۆرتەکان',
    'کڕین','گەڕاندنەوە','دابینکەر','داواکاری','ڕێکخستن','پشکنینی نرخ','بەرواری بەسەرچوون'];
   labels.forEach((v,i)=>{const d=document.createElement('div');d.className='tile '+['blue','green','orange','red','brown'][i%5];
    const s=document.createElement('span');s.className='tile-label';s.textContent=v;d.append(s);tiles.append(d);});
  }
  const rows=document.getElementById('cart-rows');
  if(rows){
   for(let i=1;i<=3;i++){
    const tr=document.createElement('tr');
    for(const s of ['کاڵای تاقیکردنەوە '+i,'٢','٢٥٬٠٠٠','٥٠٬٠٠٠','—']){
     const td=document.createElement('td');td.textContent=s;tr.append(td);
    }rows.append(tr);
   }
   const empty=document.getElementById('empty-cart');if(empty)empty.hidden=true;
   const count=document.getElementById('item-count');if(count)count.textContent='٣ کاڵا — داتای ساختە';
  }
  const total=document.getElementById('subtotal');if(total)total.textContent='١٥٠٬٠٠٠';
  if(!rows){
   const tbody=document.querySelector('main table tbody');
   if(tbody&&tbody.children.length===0){
    const n=Math.max(2,Math.min(8,document.querySelectorAll('main table thead th').length||4));
    for(let i=0;i<4;i++){const tr=document.createElement('tr');
      for(let j=0;j<n;j++){const td=document.createElement('td');td.textContent=j===0?'کاڵای تاقیکردنەوە '+(i+1):j===1?'٢٥٬٠٠٠':'—';tr.append(td);}
      tbody.append(tr);
    }
   }
  }
  const paper=document.querySelector('body>.print-area');
  if(paper){const h=document.createElement('h1');h.textContent='پسوولەی تاقیکردنەوە';
   const p=document.createElement('p');p.textContent='داتای ساختە؛ هیچ مامەڵەیەک نەکراوە';paper.append(h,p);
  }
 });
}
async function run(){
 fs.mkdirSync(out,{recursive:true});
 const server=http.createServer(serverResponse);
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const origin='http://127.0.0.1:'+server.address().port;
 let browser;const report=[];
 try{
  browser=await chromium.launch({headless:true});
  for(const vp of sizes){
   const context=await browser.newContext({viewport:{width:vp.width,height:vp.height},reducedMotion:'reduce',locale:'ar-IQ'});
   await context.route('**/*',route=>route.request().url().startsWith(origin+'/')?route.continue():route.abort());
   for(const file of screens){
    const page=await context.newPage(),errors=[];
    page.on('pageerror',err=>errors.push(err.message));
    const response=await page.goto(origin+'/'+file,{waitUntil:'load',timeout:30000});
    await page.evaluate(()=>document.fonts?.ready);
    await fixtures(page);
    const info=await page.evaluate(()=>({
     dir:document.documentElement.dir,lang:document.documentElement.lang,
     clientWidth:document.documentElement.clientWidth,
     documentWidth:Math.max(document.documentElement.scrollWidth,document.body.scrollWidth),
     offenders:[...document.querySelectorAll('body *')].filter(e=>{
      const r=e.getBoundingClientRect();
      return (r.right>window.innerWidth+2||r.left< -2)&&!e.closest('.table-wrap');
     }).slice(0,10).map(e=>({tag:e.tagName,className:String(e.className?.baseVal??e.className).slice(0,90),
      text:e.textContent?.trim().slice(0,36),left:Math.round(e.getBoundingClientRect().left),
      right:Math.round(e.getBoundingClientRect().right)})),
     glassLoaded:[...document.styleSheets].some(s=>s.href?.includes('glass-system.css')),
     cartWidth:document.querySelector('.cart-panel')?.getBoundingClientRect().width||null,
     paymentWidth:document.querySelector('.payment-panel')?.getBoundingClientRect().width||null
    }));
    await page.screenshot({path:path.join(out,file.replace('.html','')+'-'+vp.name+'.png'),
     fullPage:true,animations:'disabled'});
    report.push({file,viewport:vp.name,status:response.status(),errors,...info});
    await page.close();
   }
   await context.close();
  }
  const pctx=await browser.newContext({viewport:{width:850,height:1100}});
  await pctx.route('**/*',route=>route.request().url().startsWith(origin+'/')?route.continue():route.abort());
  const printed=await pctx.newPage();
  await printed.goto(origin+'/sale.html',{waitUntil:'load'});
  await fixtures(printed);
  await printed.emulateMedia({media:'print'});
  const visible=await printed.evaluate(()=>{
   const node=document.querySelector('body>.print-area');
   return Boolean(node&&getComputedStyle(node).display!=='none');
  });
  await printed.screenshot({path:path.join(out,'sale-print-synthetic.png'),fullPage:true});
  await pctx.close();
  fs.writeFileSync(path.join(out,'report.json'),JSON.stringify({report,printAreaVisible:visible},null,2));
  const failures=[];
  for(const row of report){
   const context=row.file+' '+row.viewport;
   if(row.status!==200)failures.push(context+' local HTTP '+row.status);
   if(row.lang!=='ckb'||row.dir!=='rtl')failures.push(context+' expected Sorani RTL');
   if(!row.glassLoaded)failures.push(context+' design stylesheet not loaded');
   if(row.documentWidth-row.clientWidth>2){
    const problem={page:row.file,viewport:row.viewport,width:row.documentWidth-row.clientWidth,offenders:row.offenders};
    console.error('OVERFLOW DIAGNOSTIC '+JSON.stringify(problem));
    failures.push(context+' document overflow '+problem.width+'px');
   }
   if(row.errors.length)failures.push(context+' browser exceptions: '+row.errors.join('; '));
  }
  if(!visible)failures.push('sale print media sheet hidden');
  console.log('AUDIT: '+report.length+' Chromium screenshots from '+screens.length+' source HTML screens; '+failures.length+' violations.');
  for(const issue of failures)console.error('VISUAL QA ISSUE: '+issue);
  assert.deepEqual(failures,[],'visual smoke QA issues require responsive fixes');
  console.log('PASS: '+report.length+' Chromium viewport renders, offline fictional DOM only, + print-media snapshot.');
 }finally{
  if(browser)await browser.close();
  await new Promise(resolve=>server.close(resolve));
 }
}
run().catch(err=>{console.error('CRYSTAL QA FAILED: '+err.message);process.exitCode=1;});
