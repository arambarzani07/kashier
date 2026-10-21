#!/usr/bin/env node
'use strict';
// Optional browser QA: requires Playwright and a Chromium executable. Every
// business response is intercepted; no request is sent to a business service.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto');
const {chromium}=require('playwright');
const F=require('../tests/fixtures/design-data.cjs');
const root=path.resolve(__dirname,'..');
const output=process.env.KASHIER_UI_AUDIT_OUTPUT||'/tmp/kashier-populated-audit';
const widths=(process.env.KASHIER_UI_AUDIT_WIDTHS||'1440,390,320').split(',').map(Number);
const profiles=(process.env.KASHIER_UI_AUDIT_PROFILES||'normal,accessible').split(',');
const only=process.env.KASHIER_UI_AUDIT_PAGES?.split(',');
const pages=fs.readdirSync(root).filter(n=>n.endsWith('.html')&&(!only||only.includes(n))).sort();
const expected={'index':'#home-summary','daily':'#daily-paper','price-check':'#price-result','quick-return':'#quick-return-result','labels':'.product-label','stock-adjustment':'#adjust-form-panel','waste':'#adjust-form-panel','export':'#export-preview','verify-export':'#verify-result'};
const queries={product:'?id='+F.owner,customer:'?id='+F.uuid(2),supplier:'?id='+F.uuid(2),statement:'?id='+F.owner,'supplier-statement':'?id='+F.owner,'customer-allocations':'?id='+F.uuid(2),receipt:'?id='+F.owner,'purchase-receipt':'?id='+F.owner,'stock-adjustment':'?product='+F.products[0].id,waste:'?product='+F.products[0].id,'return-document':'?source=sale&kind=full&id='+F.owner};
const reports={'sales-report':'salesReport','purchase-report':'purchaseReport','cash-statement':'cashStatement','expense-report':'expense'};
const populated=new Set(['index','sale','purchase','products','stock','customers','suppliers','customer','supplier','product','customer-allocations','receipts','purchase-receipts','statement','supplier-statement','daily','sales-report','purchase-report','cash-statement','expense-report','customer-balances','supplier-balances','stocktake','expiry','cash','returns','purchase-returns','supplier-payables','return-document','receipt','purchase-receipt','labels','price-check','quick-return','product-import','export','verify-export','stock-adjustment','waste']);
fs.mkdirSync(output,{recursive:true});
async function prepare(p,base){
 const states=[];
 if(reports[base]){const r=F.seed[reports[base]],dates=p.locator('main input[type=date]');await dates.nth(0).fill(r.from);await dates.nth(1).fill(r.to);await p.locator('main form').first().evaluate(e=>e.requestSubmit());}
 if(['statement','supplier-statement','stocktake','customer-balances','supplier-balances','expiry'].includes(base))await p.locator('main form').first().evaluate(e=>e.requestSubmit());
 if(base==='price-check'){await p.locator('#price-query').fill('تاقیکردنەوە');await p.locator('#price-form').evaluate(e=>e.requestSubmit());await p.waitForTimeout(40);states.push({state:'search-results',...await p.evaluate(metrics)});if(await p.locator('#price-choices button').count())await p.locator('#price-choices button').first().click();}
 if(base==='quick-return'){await p.locator('#receipt-code').fill('K-'+F.sale.receipt_no);await p.locator('#quick-return-form').evaluate(e=>e.requestSubmit());}
 if(base==='labels'){await p.locator('.label-result button').first().click();}
 if(base==='product-import'){const csv='name,barcode,sale_price\n'+F.products.map(x=>`"${x.name}",${x.barcode},${x.sale_price}`).join('\n');await p.locator('#import-file').setInputFiles({name:'synthetic-ui.csv',mimeType:'text/csv',buffer:Buffer.from(csv)});}
 if(base==='export')await p.locator('#export-prepare').click();
 if(base==='verify-export'){const data=Buffer.from(JSON.stringify(F.rpc('export_owner_data')));await p.locator('#verify-file').setInputFiles({name:'synthetic-ui.json',mimeType:'application/json',buffer:data});await p.locator('#verify-hash').fill(crypto.createHash('sha256').update(data).digest('hex'));await p.locator('#verify-form').evaluate(e=>e.requestSubmit());}
 await p.waitForTimeout(60);
 return states;
}
function metrics(){
 const visible=e=>!!(e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden');
 const name=e=>e.id?'#'+e.id:e.tagName.toLowerCase()+(e.className?'.'+String(e.className).trim().replace(/\s+/g,'.'):'');
 const controls=[...document.querySelectorAll('button:not(.tile),input:not([type=checkbox]):not([type=radio]):not([type=hidden]),select,textarea,a.primary,a.secondary,.returns-action,.payables-action,.profile-card .count-actions a')].filter(visible).map(e=>{
  const c=getComputedStyle(e),button=e.matches('button,a'),primary=e.matches('.primary,.complete-sale,.submit-button,.return-button,#password-save,#label-print,#tender-exact,#export-download')||e.form&&e.type==='submit'&&!e.matches('.secondary,.danger,.danger-solid'),danger=e.matches('.danger,.danger-solid,.danger-link,.delete-item');
  const colorCheck=button&&!e.closest('.topbar')&&!e.matches('.visibility-control')&&document.documentElement.dataset.uiContrast!=='high';
  const expectedBg=primary?'rgb(25, 95, 196)':danger?'rgb(255, 240, 242)':'rgb(237, 243, 252)';
  return {element:name(e),radius:c.borderTopLeftRadius,height:e.getBoundingClientRect().height,font:c.fontFamily,bg:c.backgroundColor,type:e.type,colorMismatch:colorCheck&&c.backgroundColor!==expectedBg,expectedBg};
 });
 const bad=controls.filter(c=>c.radius!=='10px'||c.height<43.5||!c.font.startsWith('Tahoma')||c.colorMismatch);
 const cards=[...document.querySelectorAll('.cart-panel,.payment-panel,.stocktake-controls,.statement-controls,.statement-paper,.account-card,.returns-filter,.returns-list,.return-document-paper,.labels-controls,.label-queue-panel,.price-search,.price-matches,.quick-return-search,.quick-return-result,.customer-identity,.supplier-identity,.profile-card,.profile-history,.receipt-paper,.access-panel,.identity-panel')].filter(visible).map(e=>({element:name(e),radius:getComputedStyle(e).borderTopLeftRadius}));
 const header=document.querySelector('.topbar');
 const large=document.documentElement.dataset.uiText==='large';
 const tableMismatches=[...document.querySelectorAll('main th,main td')].filter(visible).map(e=>{const c=getComputedStyle(e);return {element:name(e),font:c.fontSize,padding:c.padding,expected:large?'16px':e.tagName==='TH'?'12px':'13px'};}).filter(c=>c.font!==c.expected||c.padding!=='12px');
 const notices=[...document.querySelectorAll('[role=status],[role=alert]')].filter(visible).map(e=>({id:e.id,text:e.textContent.trim()})).filter(e=>e.text);
 const revealed=[...document.querySelectorAll('main [id]')].filter(visible).map(e=>e.id);
 return {width:innerWidth,scrollWidth:document.documentElement.scrollWidth,font:getComputedStyle(document.body).fontFamily,header:header?getComputedStyle(header).backgroundColor:null,controls:controls.length,controlMismatches:bad,tableMismatches:[...new Map(tableMismatches.map(c=>[JSON.stringify(c),c])).values()],cards:cards.length,cardMismatches:cards.filter(c=>c.radius!=='16px'),rows:[...document.querySelectorAll('main tbody tr')].filter(visible).length,notices,revealed,heading:document.querySelector('main h1')?.textContent};
}
(async()=>{
 const server=http.createServer((req,res)=>{const file=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}try{res.setHeader('Content-Type',file.endsWith('.css')?'text/css':file.endsWith('.js')?'text/javascript':'text/html');res.end(fs.readFileSync(file));}catch{res.writeHead(404);res.end();}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;
 const results=[],printChecks=[];
 try{for(const width of widths)for(const profile of profiles){
  const browser=await chromium.launch({executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--no-zygote','--single-process','--disable-gpu']});
  try{const context=await browser.newContext({viewport:{width,height:1000}});let missing=[],calls=[],pageErrors=[];
   await context.route('**/*',async route=>{const req=route.request(),url=new URL(req.url());if(url.origin===origin)return route.continue();
    const rpc=url.pathname.startsWith('/rest/v1/rpc/')?url.pathname.split('/').pop():null;
    // Exact host + method/path allowlist: even an accidental write cannot escape.
    if(url.hostname!=='dhfyqxdfwhxlipbsasqf.supabase.co'||!(req.method()==='GET'||req.method()==='POST'&&rpc&&(rpc.startsWith('get_')||rpc==='search_receipts'||rpc==='export_owner_data'))){missing.push('Blocked '+req.method()+' '+url.pathname);return route.abort();}
    try{const b=req.postData()?JSON.parse(req.postData()):{},r=F.response(url,b);calls.push(url.pathname);return route.fulfill({status:200,headers:{'content-type':'application/json','access-control-allow-origin':'*','access-control-expose-headers':'content-range',...r.headers},body:JSON.stringify(r.data)});}catch(e){missing.push(e.message);return route.fulfill({status:500,contentType:'application/json',body:JSON.stringify({message:'ui_fixture_missing'})});}
   });
   await context.addInitScript(({owner,products,longNote,profile,edge})=>{
    sessionStorage.clear();localStorage.clear();sessionStorage.setItem('kashier.auth.v1',JSON.stringify({user:{id:owner},access_token:'synthetic-ui-session-not-a-real-token',refresh_token:'synthetic-ui-refresh',expires_at:Math.floor(Date.now()/1000)+3600}));
    const items=products.slice(0,15).map(p=>({productId:p.id,name:p.name,barcode:p.barcode,quantityUnits:1000,price:edge?p.sale_price:1500}));
    sessionStorage.setItem('kashier.sale-draft.v2.'+owner,JSON.stringify({version:1,items,mode:'cash',selectedCustomer:null,customer:'تاقیکردنەوە',note:longNote,discount:'0',received:edge?'15000000000':'23000',posting:null,held:[]}));
    sessionStorage.setItem('kashier.purchase-draft.v1.'+owner,JSON.stringify({version:1,items,accounting:'untracked',selectedSupplier:null,paid:'0',supplier:'تاقیکردنەوە',invoice:'INV-TEST',note:longNote,posting:null}));
    if(profile==='accessible')localStorage.setItem('kashier.device-preferences.v1',JSON.stringify({version:1,text:'large',contrast:'high',motion:'reduce'}));
   },{owner:F.owner,products:F.products,longNote:F.longNote,profile,edge:process.env.KASHIER_UI_AUDIT_EDGE==='1'});
   const p=await context.newPage();p.setDefaultTimeout(3000);p.on('pageerror',e=>pageErrors.push(e.message));
   for(const file of pages){const base=file.replace('.html','');missing=[];calls=[];pageErrors=[];let actionError=null,states=[];
    try{await p.goto(origin+'/'+file+(queries[base]||''),{waitUntil:'networkidle'});states=await prepare(p,base);}catch(e){actionError=e.message;}
    const m=await p.evaluate(metrics),dialogs=[];if(populated.has(base)){const selector=expected[base]||'main tbody tr';const loaded=await p.locator(selector).evaluateAll(es=>es.some(e=>e.getClientRects().length));if(!loaded)actionError=(actionError||'')+' Expected populated state absent: '+selector;}
    for(const d of await p.locator('dialog').all()){await d.evaluate(e=>{if(!e.open)e.showModal();});const dm=await p.evaluate(metrics);const bounds=await d.boundingBox();dialogs.push({id:await d.getAttribute('id'),fits:bounds.x>=-1&&bounds.x+bounds.width<=width+1,mismatches:dm.controlMismatches});await d.evaluate(e=>e.close());}
    m.controlMismatches.push(...dialogs.flatMap(d=>d.mismatches),...states.flatMap(s=>s.controlMismatches));m.controlMismatches=[...new Map(m.controlMismatches.map(v=>[JSON.stringify(v),v])).values()];const result={file,profile,...m,calls:[...new Set(calls)],fixtureErrors:missing,errors:pageErrors,actionError,dialogs,states};results.push(result);
    if(process.env.KASHIER_UI_AUDIT_SCREENSHOTS==='1')await p.screenshot({path:path.join(output,`${base}-${width}-${profile}.png`),fullPage:true});
    if(process.env.KASHIER_UI_AUDIT_PRINT==='1'&&['receipt','purchase-receipt'].includes(base)){
     for(const paper of ['58','80','a4']){
      await p.evaluate(value=>KashierPreferences.set({receiptPaper:value}),paper);
      await p.emulateMedia({media:'print'});
      const check=await p.locator('#receipt').evaluate(e=>({width:e.getBoundingClientRect().width,scrollWidth:e.scrollWidth,wrapperOverflow:getComputedStyle(e.querySelector('.table-wrap')).overflow,rows:e.querySelectorAll('tbody tr').length}));
      printChecks.push({file,paper,...check});
      await p.pdf({path:path.join(output,`${base}-${paper}.pdf`),width:paper==='a4'?'210mm':paper+'mm',height:paper==='a4'?'297mm':'300mm',preferCSSPageSize:true,printBackground:true});
     }
     await p.emulateMedia({media:'screen'});
    }
    fs.writeFileSync(path.join(output,'results.json'),JSON.stringify(results,null,2));
   }
  }finally{await browser.close();}
 }
 }finally{server.close();}
 const summary={screens:pages.length,renders:results.length,controls:results.reduce((s,r)=>s+r.controls,0),overflow:results.filter(r=>r.scrollWidth>r.width+1).map(r=>[r.file,r.width,r.profile]),errors:results.filter(r=>r.errors.length||r.fixtureErrors.length||r.actionError).map(r=>({file:r.file,width:r.width,profile:r.profile,errors:r.errors,fixture:r.fixtureErrors,action:r.actionError})),controlMismatches:results.flatMap(r=>r.controlMismatches.map(m=>({file:r.file,width:r.width,profile:r.profile,...m}))),tableMismatches:results.flatMap(r=>r.tableMismatches.map(m=>({file:r.file,width:r.width,profile:r.profile,...m}))),cardMismatches:results.flatMap(r=>r.cardMismatches.map(m=>({file:r.file,width:r.width,...m}))),dialogOverflow:results.flatMap(r=>r.dialogs.filter(d=>!d.fits).map(d=>({file:r.file,width:r.width,...d})))};
 fs.writeFileSync(path.join(output,'summary.json'),JSON.stringify(summary,null,2));console.log(JSON.stringify({...summary,controlMismatches:summary.controlMismatches.slice(0,35)},null,2));
 fs.writeFileSync(path.join(output,'print-checks.json'),JSON.stringify(printChecks,null,2));
 if(printChecks.some(c=>c.wrapperOverflow!=='visible'||c.scrollWidth>c.width+2||c.rows!==15))throw Error('Receipt print layout failed');
 process.exitCode=summary.overflow.length||summary.errors.length||summary.controlMismatches.length||summary.tableMismatches.length||summary.cardMismatches.length||summary.dialogOverflow.length?1:0;
})().catch(e=>{console.error(e);process.exitCode=1;});
