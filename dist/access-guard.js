(function(){'use strict';
if(typeof KashierData==='undefined'||typeof KashierAccess==='undefined')return;
const path=location.pathname.split('/').pop()||'index.html';if(path==='auth.html')return;
const actor=KashierData.userId(),lock='kashier.screen-locked.v1.'+actor;
const go=()=>location.replace('auth.html?next='+encodeURIComponent(path+location.search));
if(!actor){go();return;}
try{if(sessionStorage.getItem(lock)==='true'){go();return;}}catch{go();return;}
let alive=true;
window.addEventListener('pagehide',()=>{alive=false;});
window.addEventListener('pageshow',e=>{if(e.persisted)location.reload();});
KashierData.getAccessProfile().then(p=>{if(!alive||KashierData.userId()!==actor)return;KashierAccess.profile(p);if(p.needs_username||p.must_change){go();return;}
 const scoped=['cashier.html','manager.html','repayment.html','staff-refund.html','staff-partial.html','staff-cash.html','account-settings.html'];
 if(p.role!=='owner'&&(!scoped.includes(path)||(path!=='account-settings.html'&&new URLSearchParams(location.search).get('owner')!==p.owner_id))){location.replace(KashierAccess.home(p));return;}
 const button=document.createElement('button');button.type='button';button.textContent='قوفڵ / گۆڕینی کارمەند';button.className='access-lock';button.addEventListener('click',()=>{try{sessionStorage.setItem(lock,'true');}catch{}go();});document.body.append(button);
}).catch(()=>{if(alive)go();});
})();
