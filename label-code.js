(function(root){
 'use strict';
 const LIMIT=500;
 function integer(value,min,max){if(!/^\d+$/.test(String(value)))throw Error('ژمارەیەکی تەواو بنووسە.');const n=Number(value);if(!Number.isSafeInteger(n)||n<min||n>max)throw Error('ژمارە لە سنووری ڕێگەپێدراو نییە.');return n;}
 function dimensions(width,height){return {width:integer(width,40,120),height:integer(height,30,80)};}
 function copies(value){return integer(value,1,100);}
 function total(items){const n=items.reduce((s,i)=>s+copies(i.copies),0);if(n>LIMIT)throw Error('لە هەر چاپێکدا زیاتر لە ٥٠٠ لیبڵ ڕێگەپێدراو نییە.');return n;}
 function encode(value,width,encoder){if(typeof value!=='string'||!value.length)throw Error('کاڵاکە بارکۆدی نییە.');if(!/^[\x20-\x7e]+$/.test(value))throw Error('بارکۆدی ئەم کاڵایە نیشانەی پشتگیری نەکراوی تێدایە؛ بارکۆدی هێڵی ستاندارد پیتی لاتینی و ژمارە دەگرێتەوە.');const result={};encoder(result,value,{format:'CODE128',displayValue:false,margin:0});const bits=result.encodings?.map(x=>x.data).join('');if(!bits||! /^[01]+$/.test(bits))throw Error('بارکۆدەکە دروست نەکرا.');const modules=bits.length+20;if(width/modules<0.25)throw Error('بارکۆدەکە بۆ ئەم پانییە زۆر درێژە؛ پانیی لیبڵ زیاد بکە یان بارکۆدەکە لە لیبڵی نرخ لاببە.');return {bits,modules,quiet:10};}
 root.LabelCode={dimensions,copies,total,encode};
 if(typeof module==='object'&&module.exports)module.exports=root.LabelCode;
})(globalThis);
