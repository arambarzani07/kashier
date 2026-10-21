/* Sorani presentation only: never translate stored data, IDs or protocol values. */
(function(root){
 'use strict';
 function message(value){
  const text=typeof value==='string'?value:'';
  return /[\u0600-\u06ff]/.test(text)&&!/[A-Za-z]/.test(text)?text:'کردارەکە تەواو نەبوو؛ زانیارییەکان و پەیوەندییەکەت بپشکنە و دووبارە هەوڵ بدەرەوە.';
 }
 function validation(field){
  const v=field.validity;
  if(!v||v.valid)return '';
  if(v.customError&&/[\u0600-\u06ff]/.test(field.validationMessage||''))return field.validationMessage;
  if(v.valueMissing)return field.type==='checkbox'?'بۆ بەردەوامبوون، ئەم پشتڕاستکردنەوەیە هەڵبژێرە.':field.type==='file'?'فایلێک هەڵبژێرە.':'ئەم خانەیە پڕ بکەرەوە.';
  if(v.typeMismatch)return field.type==='email'?'ناونیشانی پۆستی ئەلیکترۆنی بە دروستی بنووسە.':'زانیارییەکە بە شێوەی داواکراو بنووسە.';
  if(v.tooShort)return 'نووسینەکە زۆر کورتە؛ ژمارەی پیتی پێویست پڕ بکەرەوە.';
  if(v.tooLong)return 'نووسینەکە زۆر درێژە؛ کەمتر بنووسە.';
  if(v.rangeUnderflow)return 'بڕەکە لە کەمترین بڕی ڕێگەپێدراو کەمترە.';
  if(v.rangeOverflow)return 'بڕەکە لە زۆرترین بڕی ڕێگەپێدراو زیاترە.';
  if(v.stepMismatch)return 'بڕەکە بە پێی هەنگاوی ژمارەی ڕێگەپێدراو بنووسە.';
  if(v.badInput)return 'ژمارەیەکی دروست بنووسە.';
  if(v.patternMismatch)return 'نووسینەکە لەگەڵ ڕێنمایی ئەم خانەیە ناگونجێت.';
  return 'زانیاریی ئەم خانەیە بپشکنە.';
 }
 const doc=root.document;
 function refreshFiles(){
  for(const field of doc?.querySelectorAll?.('input[data-kurdish-file]')||[]){
   const label=doc.getElementById(field.id+'-selected-name');
   if(label)label.textContent=field.files?.[0]?.name||'هیچ فایلێک هەڵنەبژێردراوە';
  }
 }
 root.KashierLocale={message,validation,refreshFiles};
 doc?.addEventListener?.('invalid',event=>{const field=event.target;if(typeof field?.setCustomValidity==='function')field.setCustomValidity(validation(field));},true);
 for(const name of ['input','change'])doc?.addEventListener?.(name,event=>{if(typeof event.target?.setCustomValidity==='function')event.target.setCustomValidity('');if(event.target?.type==='file')refreshFiles();},true);
 refreshFiles();
})(globalThis);
