#!/usr/bin/env node
'use strict';
// Public layout review: no Auth, database, account details or business numbers.
const fs=require('node:fs'),path=require('node:path'),root=path.resolve(__dirname,'..');
const allowed=new Set(['preferences.js','home-navigation.js','app.js','returns-tile.js','quick-return-tile.js','purchase-returns-tile.js']);
let html=fs.readFileSync(path.join(root,'index.html'),'utf8');
html=html.replace(/<script\s+src="([^"]+)"[^>]*><\/script>/g,(tag,src)=>allowed.has(src)?tag:'');
html=html.replace(/<section class="account-panel"[\s\S]*?<\/section>/,'').replace(/<section id="home-summary"[\s\S]*?<\/section>/,'');
html=html.replace('<title>کاشێر — سەرەکی</title>','<title>کاشێر — پێشبینینی دیزاین</title>');
html=html.replace('<nav class="quick-links"','<p class="preview-notice" role="note">پێشبینینی دیزاین · داتای هەژمار پیشان نادرێت. <a href="auth.html">چوونەژوورەوە بۆ کارکردن ←</a></p><nav class="quick-links"');
fs.writeFileSync(path.join(root,'design-preview.html'),html);
