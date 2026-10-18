#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'dist');
const errors = [];
let pages = 0, references = 0, assets = 0;
function files(dir) {
  return fs.readdirSync(dir, {withFileTypes:true}).flatMap(entry => {
    const name = path.join(dir, entry.name);
    return entry.isDirectory() ? files(name) : [name];
  });
}
function checkReference(file, raw) {
  if (/^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(raw)) return;
  const pathname = raw.split(/[?#]/, 1)[0];
  if (!pathname) return;
  let decoded;
  try { decoded = decodeURIComponent(pathname); }
  catch { errors.push(`${path.relative(root,file)}: invalid URL ${raw}`); return; }
  const target = decoded.startsWith('/')
    ? path.resolve(output, '.' + decoded)
    : path.resolve(path.dirname(file), decoded);
  references++;
  if (!target.startsWith(output + path.sep) && target !== output) {
    errors.push(`${path.relative(root,file)}: reference escapes dist: ${raw}`);
  } else if (!fs.existsSync(target) || !fs.statSync(target).isFile()) {
    errors.push(`${path.relative(root,file)}: missing file ${raw}`);
  }
}
if (!fs.existsSync(path.join(output,'index.html'))) {
  console.error('Static output is missing dist/index.html');
  process.exit(1);
}
for (const file of files(output)) {
  const relative = path.relative(output,file);
  const source = path.join(root,relative);
  const content = fs.readFileSync(file);
  assets++;
  if (!content.length) errors.push(`dist/${relative}: empty file`);
  if (fs.existsSync(source) && fs.statSync(source).isFile() &&
      !content.equals(fs.readFileSync(source))) {
    errors.push(`dist/${relative}: differs from source ${relative}`);
  }
  if (file.endsWith('.html')) {
    pages++;
    for (const match of content.toString().matchAll(/\b(?:src|href)\s*=\s*["']([^"']+)["']/gi)) {
      if (/\.(?:css|js|html|svg|png|jpe?g|webp|ico|woff2?|csv)(?:[?#]|$)/i.test(match[1]))
        checkReference(file,match[1]);
    }
  } else if (file.endsWith('.css')) {
    for (const match of content.toString().matchAll(/url\(\s*["']?([^\s"')]+)["']?\s*\)/gi))
      checkReference(file,match[1]);
    for (const match of content.toString().matchAll(/@import\s+["']([^"']+)["']/gi))
      checkReference(file,match[1]);
  }
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}
console.log(`Static deployment verified: ${pages} pages, ${assets} files, ${references} local references; source/output parity passed.`);
