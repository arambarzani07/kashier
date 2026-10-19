(function(){
 'use strict';
 const grid=document.querySelector('#tiles');if(!grid||grid.querySelector('[data-module="supplier-payables"]'))return;
 const button=document.createElement('button');button.type='button';button.className='tile purple';button.dataset.module='supplier-payables';button.setAttribute('aria-label','قەرزە ماوەکانی کڕین');button.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16v12H4zM8 10h8M8 14h5"/></svg>';
 const label=document.createElement('span');label.className='tile-label';label.textContent='قەرزە ماوەکانی کڕین';button.append(label);button.addEventListener('click',()=>{location.href='supplier-payables.html';});
 const anchor=grid.querySelector('[data-module="supplier-debt"]')||grid.querySelector('[data-module="purchase-receipts"]');if(anchor?.nextSibling)grid.insertBefore(button,anchor.nextSibling);else if(anchor)anchor.after(button);else grid.append(button);
})();
