(function(){
 'use strict';
 const grid=document.querySelector('#tiles');if(!grid||grid.querySelector('[data-module="quick-return"]'))return;
 const button=document.createElement('button');button.type='button';button.className='tile blue';button.dataset.module='quick-return';button.setAttribute('aria-label','گەڕاندنەوەی خێرا');
 button.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 3v6M7 3v6M10 3v6M14 3v6M17 3v6M20 3v6M8 13l-5 4 5 4M3 17h12a5 5 0 0 0 0-10h-1"/></svg>';
 const label=document.createElement('span');label.className='tile-label';label.textContent='گەڕاندنەوەی خێرا';button.append(label);button.addEventListener('click',()=>{location.href='quick-return.html';});
 const returns=grid.querySelector('[data-module="returns"]');if(returns?.nextSibling)grid.insertBefore(button,returns.nextSibling);else if(returns)returns.after(button);else{const sales=grid.querySelector('[data-module="sales"]');if(sales?.nextSibling)grid.insertBefore(button,sales.nextSibling);else grid.append(button);}
})();
