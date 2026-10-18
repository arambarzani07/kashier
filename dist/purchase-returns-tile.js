(function(){
 'use strict';
 const grid=document.querySelector('#tiles');if(!grid||grid.querySelector('[data-module="purchase-returns"]'))return;
 const button=document.createElement('button');button.type='button';button.className='tile green';button.dataset.module='purchase-returns';button.setAttribute('aria-label','گەڕاندنەوەکانی کڕین');
 button.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 3L3 8l5 5M3 8h12a6 6 0 0 1 0 12H7"/></svg>';
 const label=document.createElement('span');label.className='tile-label';label.textContent='گەڕاندنەوەکانی کڕین';button.append(label);button.addEventListener('click',()=>{location.href='purchase-returns.html';});
 const receipts=grid.querySelector('[data-module="purchase-receipts"]');if(receipts?.nextSibling)grid.insertBefore(button,receipts.nextSibling);else if(receipts)receipts.after(button);else grid.append(button);
})();
