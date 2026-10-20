(function(root){'use strict';
const groups={
 sales:['sale','sales','returns','quick-return','price-check'],
 inventory:['shelf','barcode','new-product','products','purchases','purchase-receipts','purchase-returns','expired','low-stock','stocktake','stock','waste'],
 finance:['cash-out','expenses','supplier-debt','debts','repayments','installment-alerts','installment-book','installment-report','cashbox','daily-close'],
 reports:['profits','sales-stocktake','cash-statement','customer-statement','purchase-statement','purchase-stocktake','cash-report','daily'],
 administration:['employees','users','backup','utilities','settings']
};
const normalize=s=>String(s).replace(/ڕ/g,'ر').replace(/ێ/g,'ی').replace(/[کك]/g,'ک').replace(/[يى]/g,'ی').replace(/\s+/g,'').toLowerCase();
const matches=(id,label,query,group='all')=>(group==='all'||(groups[group]||[]).includes(id))&&normalize(label).includes(normalize(query));
root.HomeNavigation={groups,normalize,matches};if(typeof module==='object'&&module.exports)module.exports=root.HomeNavigation;
})(globalThis);
