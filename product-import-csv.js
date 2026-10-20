(function(root){'use strict';
const maxBytes=1048576,maxRows=500;
function parse(text){
 if(typeof text!=='string'||new TextEncoder().encode(text).length>maxBytes)throw Error('فایل دەبێت کۆدکردنی گشتی پیتەکان بێت و لە ١ مێبی‌بایت گەورەتر نەبێت.');
 text=text.replace(/^\uFEFF/,'');const rows=[];let row=[],field='',state='start';
 const cell=()=>{row.push(field);field='';state='start';};
 const line=()=>{cell();rows.push(row);row=[];if(rows.length>maxRows+1)throw Error('لە هەر فایلێکدا تا ٥٠٠ کاڵا ڕێگەپێدراوە.');};
 for(let i=0;i<text.length;i++){const c=text[i];if(state==='quoted'){if(c==='"'){if(text[i+1]==='"'){field+='"';i++;}else state='closed';}else field+=c;continue;}
  if(c===','){cell();continue;}if(c==='\r'||c==='\n'){if(c==='\r'&&text[i+1]==='\n')i++;line();continue;}
  if(state==='closed')throw Error('دوای داخستنی دەقی نێوان کۆتەیشن تەنها کۆما یان کۆتایی ڕیز ڕێگەپێدراوە.');
  if(c==='"'){if(state!=='start')throw Error('کۆتەیشن لە خشتەی داتاکەدا نادروستە.');state='quoted';}else{field+=c;state='plain';}
 }
 if(state==='quoted')throw Error('کۆتەیشنێک لە فایلەکەدا دانەخراوە.');if(field!==''||row.length||state!=='start')line();
 const header=rows.shift()||[];if(header.length!==3||!['name,barcode,sale_price','ناو,بارکۆد,نرخی_فرۆشتن'].includes(header.join(',')))throw Error('سەری ستوونەکان دەبێت بە ڕیز ناو، بارکۆد، نرخی_فرۆشتن بێت.');
 if(!rows.length)throw Error('فایلەکە هیچ کاڵایەکی تێدا نییە.');const seen=new Set();
 return rows.map((r,i)=>{const fail=message=>{throw Error('ڕیزی '+(i+2)+': '+message);};if(r.length!==3)fail('دەبێت سێ ستوون هەبێت.');const [name,code,price]=r.map(v=>v.trim());if(!name||Array.from(name).length>150||/[\u0000-\u001f\u007f]/.test(name))fail('ناوی کاڵا نادروستە.');if(Array.from(code).length>64||/[\u0000-\u001f\u007f]/.test(code))fail('بارکۆد نادروستە.');if(!/^[0-9]{1,10}$/.test(price)||Number(price)<1||Number(price)>1000000000)fail('نرخ دەبێت ژمارەیەکی تەواو بێت لە ١ تا ١٠٠٠٠٠٠٠٠٠ دینار.');if(code&&seen.has(code))fail('بارکۆد لە فایلەکەدا دووبارەیە: '+code);if(code)seen.add(code);return {name,barcode:code||null,sale_price:Number(price)};});
}
root.ProductImportCSV={parse,maxBytes,maxRows};if(typeof module==='object'&&module.exports)module.exports=root.ProductImportCSV;
})(globalThis);
