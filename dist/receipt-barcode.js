(function(){
 'use strict';
 const paper=document.querySelector('#receipt');
 if(!paper)return;
 function attach(){
  if(paper.hidden||paper.querySelector('.receipt-scan-code')||typeof JsBarcode!=='function')return;
  const match=/ژمارەی پسوولە:\s*(K-[0-9]+)/.exec(paper.textContent||'');
  if(!match)return;
  const code=match[1],box=document.createElement('div');box.className='receipt-scan-code';box.setAttribute('aria-label','بارکۆدی پسوولە '+code);
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg'),label=document.createElement('div');label.textContent=code;label.dir='ltr';
  try{JsBarcode(svg,code,{format:'CODE128',displayValue:false,margin:0,width:1.45,height:38});}catch{return;}
  box.append(svg,label);paper.append(box);
 }
 const observer=new MutationObserver(attach);observer.observe(paper,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});attach();
})();
