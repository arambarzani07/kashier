/* Visual review only: local static previews, no account or business APIs. */
(()=>{
 'use strict';
 const screen=document.querySelector('#review-screen'),width=document.querySelector('#review-width'),frame=document.querySelector('#review-frame'),status=document.querySelector('#review-status');
 const labels=new Map([...screen.options].map(o=>[o.value,o.textContent])),widths=new Set(['320','390','768','1280']);
 let loaded=null,pending=screen.value;
 const valid=()=>labels.has(screen.value)&&widths.has(width.value);
 function title(){frame.title='پێشبینینی دیزاین — '+labels.get(screen.value);}
 function busy(on){frame.setAttribute('aria-busy',String(on));}
 function ready(){status.textContent=labels.get(loaded)+' · '+width.value+' پیکسڵ · بارکرا';}
 function loading(){busy(true);status.textContent='لە بارکردندایە: '+labels.get(pending);}
 function current(){
  try{
   const url=new URL(frame.contentWindow.location.href);
   if(url.origin!==location.origin)return null;
   for(const name of labels.keys())if(new URL(name,location.href).pathname===url.pathname)return name;
  }catch{}
  return null;
 }
 function complete(){
  const shown=current();
  if(pending&&shown&&shown!==pending)return;
  busy(false);
  if(!shown){loaded=null;pending=null;status.textContent='ئەم پەڕەیە لە پێشبینینەکان نییە؛ پەڕەیەک هەڵبژێرە یان دووبارە باری بکەرەوە.';return;}
  loaded=shown;pending=null;screen.value=shown;title();ready();
 }
 function resize(){
  if(!valid())return;
  frame.style.width=width.value+'px';frame.width=Number(width.value);
  if(loaded&&!pending)ready();
 }
 function navigate(){
  if(!valid())return;
  pending=screen.value;loaded=null;title();resize();loading();frame.src=pending;
 }
 frame.addEventListener('load',complete);
 frame.addEventListener('error',()=>{busy(false);loaded=null;pending=null;status.textContent='پەڕەکە بار نەکرا؛ دووبارە بارکردنەوە هەڵبژێرە.';});
 document.querySelector('#review-controls').addEventListener('submit',e=>e.preventDefault());
 document.querySelector('#review-reload').addEventListener('click',navigate);
 screen.addEventListener('change',navigate);width.addEventListener('change',resize);
 resize();title();loading();
 try{if(frame.contentDocument?.readyState==='complete')complete();}catch{}
})();
