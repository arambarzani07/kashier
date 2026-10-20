#!/usr/bin/env node
'use strict';
// Public layout review: no Auth, database, account details or business numbers.
const fs=require('node:fs'),path=require('node:path'),root=path.resolve(__dirname,'..');
const allowed=new Set(['preferences.js','home-navigation.js','app.js','returns-tile.js','quick-return-tile.js','purchase-returns-tile.js']);
const screens=[['index.html','design-preview.html','سەرەکی'],['staff.html','employees-preview.html','کارمەندان و دەسەڵات'],['sale.html','sale-preview.html','فرۆشتن'],['products.html','products-preview.html','کاڵاکان'],['purchase.html','purchase-preview.html','کڕین'],['statement.html','statement-preview.html','کەشف حساب'],['stocktake.html','stocktake-preview.html','جەرد'],['returns.html','returns-preview.html','گەڕاندنەوەکان'],['settings.html','settings-preview.html','ڕێکخستن'],['auth.html','auth-preview.html','چوونەژوورەوە'],['customer.html','customer-preview.html','کڕیار'],['supplier.html','supplier-preview.html','دابینکەر'],['cash.html','cash-preview.html','سندوق'],['export.html','export-preview.html','باکئەپ'],['restore.html','restore-preview.html','گەڕاندنەوەی باکئەپ'],['product-import.html','import-preview.html','هاوردەی کاڵا'],['sales-report.html','sales-report-preview.html','ڕاپۆرتی فرۆشتن'],['gross-profit.html','profit-preview.html','قازانجی فرۆشتن'],['inventory-valuation.html','valuation-preview.html','بەهای کۆگا'],['price-check.html','price-check-preview.html','پشکنینی نرخ'],['labels.html','labels-preview.html','لیبڵ و بارکۆد']];
function tabs(current){return '<nav class="preview-tabs" aria-label="پێشبینینی شاشەکان">'+screens.filter(([,url],index)=>index<4||url===current).map(([,url,label])=>`<a href="${url}"${url===current?' aria-current="page"':''}>${label}</a>`).join('')+'<a href="design-review.html">پشکنینی قەبارەی شاشە</a></nav>';}
let html=fs.readFileSync(path.join(root,'index.html'),'utf8');
html=html.replace(/<script\s+src="([^"]+)"[^>]*><\/script>/g,(tag,src)=>allowed.has(src)?tag:'');
html=html.replace(/<section class="account-panel"[\s\S]*?<\/section>/,'').replace(/<section id="home-summary"[\s\S]*?<\/section>/,'');
html=html.replace('<title>کاشێر — سەرەکی</title>','<title>کاشێر — پێشبینینی دیزاین</title>');
html=html.replace('</head>','<link rel="stylesheet" href="operations.css"></head>');
html=html.replace('<nav class="quick-links"','<p class="preview-notice" role="note">پێشبینینی دیزاین · داتای هەژمار پیشان نادرێت. <a href="auth.html">چوونەژوورەوە بۆ کارکردن ←</a></p>'+tabs('design-preview.html')+'<nav class="quick-links"');
fs.writeFileSync(path.join(root,'design-preview.html'),html);
for(const [source,target] of screens.slice(1)){
 let page=fs.readFileSync(path.join(root,source),'utf8');
 page=page.replace(/<script\b[^>]*>[\s\S]*?<\/script>/g,tag=>/^<script src="preferences.js"/.test(tag)?tag:'');
 if(!page.includes('href="operations.css"'))page=page.replace('</head>','<link rel="stylesheet" href="operations.css"></head>');
 page=page.replace(/<(input|button|select|textarea)\b([^>]*)>/g,(_,tag,attrs)=>`<${tag}${attrs.replace(/\sdisabled\b/g,'')} disabled>`);
 page=page.replace(/(<body[^>]*>)/,'$1<div class="screen-preview-bar" role="note">پێشبینینی دیزاین · فۆڕمەکان بۆ پیشاندانن؛ هیچ داتایەک ناخوێندرێتەوە یان تۆمار ناکرێت. <a href="auth.html">چوونەژوورەوە بۆ کارکردن ←</a>'+tabs(target)+'</div>');
 page=page.replace(/(<title>)[\s\S]*?(<\/title>)/,'$1کاشێر — پێشبینینی دیزاین$2');
 if(source==='staff.html'){
  page=page.replace(/(id="employee-empty"[^>]*?) hidden/,'$1');
  page=page.replace(/(<div id="employee-empty"[^>]*>)[\s\S]*?<\/div>/,'$1<h3>لیستی کارمەندەکان</h3><p>دوای چوونەژوورەوە، لیستی کارمەندەکان لێرە دەردەکەوێت.</p></div>');
 }else if(source==='sale.html'){
  page=page.replace(/(id="(?:subtotal|total|balance)">)0/g,'$1—').replace('سەبەتە هەڵگیراوەکان (٠)','سەبەتە هەڵگیراوەکان').replace('٠ کاڵا','—');
 }
 page=page.replace(/>0<\//g,'>—</');
 fs.writeFileSync(path.join(root,target),page);
}
