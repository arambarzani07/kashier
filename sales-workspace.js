(function(root){
 'use strict';
 const format=n=>new Intl.NumberFormat('ckb-IQ').format(n)+' دینار';
 function view(s){
  const valid=!!s.totals&&s.count>0;
  const credit=s.mode==='credit';
  return {
   state:s.inFlight?'لە تۆمارکردندایە…':s.pending?'ئەنجام نادیارە — پشکنینەوە پێویستە':s.refreshing?'لە پشکنینی نرخ و کۆگادایە':s.canPost?'ئامادەی پشکنین و تۆمارکردن':'مسودە — تۆمار نەکراوە',
   tone:s.pending?'warning':s.canPost?'ready':'draft',
   party:credit?(s.customerName?'کڕیار: '+s.customerName:'کڕیاری قەرز هەڵبژێرە'):(s.customerName?'کڕیار: '+s.customerName:'کڕیاری کاش'),
   cash:valid?format(credit?s.totals.received:s.totals.total):'—',
   debt:valid?format(credit?s.totals.remaining:0):'—',
   note:!valid?'سەرەتا کاڵا و بڕەکانی پارەدان بپشکنە.':!credit&&s.totals.remaining?'پارەی وەرگیراو کەمە؛ ئەم پوختەیە هێشتا ئامادەی تۆمارکردن نییە.':credit&&!s.customerName?'بۆ قەرز، کڕیارێکی تۆمارکراو هەڵبژێرە.':'بڕی سندوق پارەی وەرگیراو کەم پارەی گەڕاندنەوەیە. قەرزی نوێ، باڵانسی گشتی کڕیار نییە.'
  };
 }
 function update(s){
  const v=view(s),doc=root.document;
  for(const [id,key] of [['desk-state','state'],['desk-party','party'],['desk-cash','cash'],['desk-debt','debt'],['desk-impact-note','note']]){
   const el=doc?.getElementById(id);if(el){if(el.textContent!==v[key])el.textContent=v[key];if(id==='desk-state')el.dataset.tone=v.tone;}
  }
  return v;
 }
 root.KashierSalesDesk=Object.freeze({view,update});
 if(typeof module==='object'&&module.exports)module.exports={view};
})(typeof window==='object'?window:globalThis);
