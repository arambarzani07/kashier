const icons = {
 cart:'<path d="M2 3h3l3 13h11l3-9H6M9 20h.01M18 20h.01"/><circle cx="9" cy="20" r="1"/><circle cx="18" cy="20" r="1"/>',
 receipt:'<path d="M6 2l2 2 2-2 2 2 2-2 2 2 2-2v20l-2-2-2 2-2-2-2 2-2-2-2 2V2M9 8h6M9 12h6M9 16h4"/>',
 money:'<rect x="3" y="6" width="18" height="13" rx="2"/><circle cx="12" cy="12.5" r="3"/><path d="M6 10h.01M18 15h.01M6 3h12"/>',
 wallet:'<path d="M21 9V5H5a3 3 0 0 0 0 6h16v10H5a3 3 0 0 1-3-3V8M16 11v6h6v-6M18 14h.01"/>',
 file:'<path d="M5 2h9l5 5v15H5V2M14 2v6h5M8 12h8M8 16h8"/>',
 tag:'<path d="M3 3h9l10 10-9 9L3 12V3"/><circle cx="8" cy="8" r="1.4"/><path d="M11 12l5 5M13 10l5 5"/>',
 barcode:'<path d="M3 3v14M6 3v14M10 3v14M13 3v14M16 3v14M20 3v14M3 21h4M18 21h3"/><circle cx="15" cy="17" r="5"/><path d="M12.5 17l1.5 1.5 3-3"/>',
 box:'<path d="M2 7l10-5 10 5v11l-10 5-10-5V7M2 7l10 6 10-6M12 13v10M7 4.5l10 6"/>',
 list:'<rect x="5" y="3" width="15" height="19" rx="1"/><path d="M9 1v4M16 1v4M8 9h2M13 9h4M8 13h2M13 13h4M8 17h2M13 17h4"/>',
 calculator:'<rect x="5" y="2" width="15" height="21" rx="1"/><path d="M8 5h9v4H8V5M8 13h1M13 13h1M17 13h.1M8 17h1M13 17h1M17 17h.1M8 20h1M13 20h1M17 20h.1"/>',
 cash:'<path d="M3 10h18v11H3V10M6 10l2-7h9l2 7M9 6h6M7 14h10M7 18h2M16 18h1"/>',
 chart:'<path d="M3 3v18h19M7 17v-5h3v5M13 17V8h3v9M19 17V5h3v12M6 8l5-4 3 1 6-4"/>',
 calendar:'<rect x="3" y="5" width="19" height="17" rx="2"/><path d="M7 2v6M17 2v6M3 11h19M8 15l8 5M16 15l-8 5"/>',
 minus:'<circle cx="12" cy="12" r="10"/><path d="M7 12h10"/>',
 person:'<circle cx="9" cy="7" r="4"/><path d="M2 21v-2a7 7 0 0 1 14 0v2M17 5h5M17 9h5M18 14h4M18 18h4"/>',
 settings:'<path d="M9 2h6l1 4 4 1 3 5-3 5-4 1-1 4H9l-1-4-4-1-3-5 3-5 4-1 1-4"/><circle cx="12" cy="12" r="4"/>',
 cloud:'<path d="M6 16a5 5 0 0 1 0-10 7 7 0 0 1 13 3 4 4 0 0 1-1 8M12 12v10M8 18l4 4 4-4"/>',
 return:'<path d="M8 3L3 8l5 5M3 8h12a6 6 0 0 1 0 12H7"/>',
 check:'<path d="M5 3h14v19H5V3M9 1h6v4H9V1M8 11l2 2 5-5M8 18h8"/>',
 ledger:'<path d="M4 3h16v19H4V3M8 3v19M11 8h6M11 12h6M11 16h6M2 7h4M2 12h4M2 17h4"/>'
};
const modules = [
 ['sale','کاڵا فرۆشتن','blue','cart','شاشەی فرۆشتن: گەڕان و بارکۆد، لیستی کاڵا و هەژمارکردنی پارە.'],
 ['sales','وەسڵە فرۆشراوەکان','blue','receipt','لیستی پسوولەکانی فرۆشتن و وردەکارییەکانیان.'],
 ['cash-out','پارەوەرگرتن لە کاشێر','blue','money','تۆمارکردنی پارەی وەرگیراو لە سندوقی کاشێر.'],
 ['expenses','پارە سەرفکردن','blue','wallet','بەڕێوەبردنی پارە سەرفکراوەکان.'],
 ['waste','بەهەدەردراوەکان','blue','file','کاڵا بەهەدەردراوەکان و هۆکاری تۆمارکردنیان.'],
 ['shelf','نرخ بۆ سەر ڕەفە','blue','tag','ئامادەکردنی لیبڵی ناو و نرخی کاڵا بۆ سەر ڕەف.'],
 ['barcode','دروستکردنی بارکۆد','blue','barcode','ئامادەکردنی لیبڵ و بارکۆدی کاڵا.'],
 ['new-product','ناساندنی کاڵای نوێ','green','box','فۆرمی ناساندنی کاڵا و زانیارییەکانی.'],
 ['products','لیستی کاڵاکان','green','list','گەڕان و بینینی کاڵا تۆمارکراوەکان.'],
 ['purchases','کڕینی کاڵا','green','file','تۆمارکردنی پسوولەی کڕینی کاڵا.'],
 ['purchase-receipts','وەسڵەکڕدراوەکان','green','calculator','لیست و وردەکاریی پسوولەکانی کڕین.'],
 ['supplier-debt','قەرزی کۆمپانیاکان','green','money','بەڕێوەبردنی حساب و قەرزی کۆمپانیاکان.'],
 ['debts','لیستی قەرزەکان','orange','list','بینینی لیستی قەرزەکان و وردەکارییان.'],
 ['repayments','وەرگرتنەوەی قەرز','orange','wallet','تۆمارکردنی پارەی وەرگیراو بۆ گەڕاندنەوەی قەرز.'],
 ['installment-alerts','ئاگاداری قیست','orange','receipt','بینینی ئاگادارییەکانی قیست.'],
 ['installment-book','داشوێنی قیست','orange','ledger','بینینی تۆمار و حسابەکانی قیست.'],
 ['installment-report','ڕاپۆرتی قیست','orange','check','پوختە و ڕاپۆرتەکانی قیست.'],
 ['cashbox','قاسە','red','cash','پوختە و جووڵەکانی پارەی قاسە.'],
 ['profits','قازانجەکان','red','chart','ڕاپۆرتی قازانجەکان بە پێی تۆمارەکان.'],
 ['expired','بەسەرچووەکان','red','calendar','لیستی کاڵا بەسەرچووەکان.'],
 ['low-stock','کاڵا کەمبووەکان','red','minus','بینینی کاڵاکانی کەمبووەوە لە کۆگا.'],
 ['sales-stocktake','جەردی فرۆشراوەکان','red','receipt','جەرد و پوختەی کاڵا فرۆشراوەکان.'],
 ['cash-statement','کەشف حساب پارە','red','ledger','بینینی کشفی حساب و جووڵەی پارە.'],
 ['customer-statement','کەشف حساب کڕیار','red','person','کشفی حسابی تایبەت بە کڕیار.'],
 ['purchase-statement','کەشف حساب کڕین','red','person','کشف و وردەکاریی حسابی کڕین.'],
 ['purchase-stocktake','جەردی کڕدراوەکان','red','chart','جەرد و پوختەی کاڵا کڕدراوەکان.'],
 ['cash-report','ڕاپۆرتی پارە','red','chart','ڕاپۆرتی جووڵەکانی پارە.'],
 ['stocktake','جەردکردن','red','list','بەڕێوەبردنی جەردی کاڵا.'],
 ['users','بەکارهێنەری سیستەم','brown','person','بەڕێوەبردنی بەکارهێنەرانی سیستەم.'],
 ['backup','پاشەکەوتی داتاکان','brown','cloud','بەڕێوەبردنی پاشەکەوتی داتاکان.'],
 ['daily','دەفتەری ڕۆژانە','brown','ledger','بینینی تۆمارە ڕۆژانەکان.'],
 ['utilities','پێداویستی','brown','check','ئامراز و پێداویستییەکانی سیستەم.'],
 ['settings','ڕێکخستن','brown','settings','ڕێکخستنی شێوە و پیشاندانی ڕووکار.']
];
const grid=document.querySelector('#tiles');
const svg=(name)=>`<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name]}</svg>`;
const dialog=document.querySelector('#module-dialog');
let lastTile;
for(const [id,label,color,icon,description] of modules){
 const button=document.createElement('button');button.type='button';button.className=`tile ${color}`;button.dataset.module=id;
 button.innerHTML=svg(icon);const span=document.createElement('span');span.className='tile-label';span.textContent=label;button.append(span);
 button.addEventListener('click',()=>{if(id==='sales'){window.location.href='receipts.html';return;}if(id==='sale'){window.location.href='sale.html';return;}if(id==='products'||id==='new-product'){window.location.href=id==='new-product'?'products.html?new=1':'products.html';return;}lastTile=button;document.querySelector('#module-title').textContent=label;document.querySelector('#module-description').textContent=description;document.querySelector('#module-icon').innerHTML=svg(icon);document.querySelector('#appearance').hidden=id!=='settings';dialog.showModal();});grid.append(button);
}
const closeDialog=()=>dialog.close();document.querySelector('#close-dialog').addEventListener('click',closeDialog);document.querySelector('#return-home').addEventListener('click',closeDialog);dialog.addEventListener('close',()=>lastTile?.focus());dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();}});
const search=document.querySelector('#search');const panel=document.querySelector('#search-panel');
document.querySelector('#search-toggle').addEventListener('click',()=>{panel.hidden=!panel.hidden;if(!panel.hidden)search.focus();else{search.value='';filter();}});
const normalize=s=>s.replace(/[ڕ]/g,'ر').replace(/[ێ]/g,'ی').replace(/[کك]/g,'ک').replace(/[يى]/g,'ی').replace(/\s+/g,'').toLowerCase();
function filter(){let visible=0;for(const tile of grid.children){tile.hidden=!normalize(tile.textContent).includes(normalize(search.value));if(!tile.hidden)visible++;}document.querySelector('#no-results').hidden=visible!==0;}
search.addEventListener('input',filter);document.querySelector('#clear-search').addEventListener('click',()=>{search.value='';filter();search.focus();});
document.querySelector('#tile-size').addEventListener('change',e=>document.body.classList.toggle('compact',e.target.value==='compact'));
document.querySelector('#fullscreen').addEventListener('click',async()=>{try{if(document.fullscreenElement)await document.exitFullscreen();else await document.documentElement.requestFullscreen();}catch{document.querySelector('#fullscreen').title='پڕکردنی شاشە لەم وێبگەڕە بەردەست نییە';}});
function tick(){const now=new Date();document.querySelector('#date').textContent=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(now);document.querySelector('#time').textContent=new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Baghdad',hour:'2-digit',minute:'2-digit',second:'2-digit'}).format(now);}tick();setInterval(tick,1000);
