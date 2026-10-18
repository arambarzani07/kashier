(function(){
 'use strict';
 const grid=document.querySelector('#tiles');if(!grid||grid.querySelector('[data-module="returns"]'))return;
 const button=document.createElement('button');button.type='button';button.className='tile blue';button.dataset.module='returns';button.setAttribute('aria-label','گەڕاندنەوەکان');
 button.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 3L3 8l5 5M3 8h12a6 6 0 0 1 0 12H7"/></svg>';
 const label=document.createElement('span');label.className='tile-label';label.textContent='گەڕاندنەوەکان';button.append(label);button.addEventListener('click',()=>{location.href='returns.html';});
 const sales=grid.querySelector('[data-module="sales"]');if(sales?.nextSibling)grid.insertBefore(button,sales.nextSibling);else if(sales)sales.after(button);else grid.append(button);
})();
