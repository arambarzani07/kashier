#!/usr/bin/env node
'use strict';
// The release tree is a byte-for-byte mirror of the public source assets.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),dist=path.join(root,'dist');
fs.mkdirSync(dist,{recursive:true});
for(const entry of fs.readdirSync(root,{withFileTypes:true})){
 if(entry.isFile()&&/\.(?:html|css|js|svg|png|jpe?g|webp|ico|woff2?)$/.test(entry.name))
  fs.copyFileSync(path.join(root,entry.name),path.join(dist,entry.name));
}
