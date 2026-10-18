/* Integer IQD amounts; quantities have at most three decimal places. */
(function(root){
  'use strict';
  function quantityUnits(value){const text=String(value);if(!/^\d+(?:\.\d{1,3})?$/.test(text))throw new Error('بڕ دەبێت ژمارەیەکی ئەرێنی بێت، تا سێ خانەی دەهەمی.');const units=Math.round(Number(text)*1000);if(!Number.isSafeInteger(units)||units<1||units>10000000)throw new Error('بڕ دەبێت لە نێوان ٠.٠٠١ و ١٠٠٠٠ بێت.');return units;}
  function money(value,max=100000000000000){const text=String(value);if(!/^\d+$/.test(text))throw new Error('بڕی پارە دەبێت ژمارەی تەواو و نەنەرێنی بێت.');const n=Number(text);if(!Number.isSafeInteger(n)||n>max)throw new Error('بڕی پارە لە سنووری ڕێگەپێدراو زیاترە.');return n;}
  function lineTotal(item){return Number((BigInt(item.quantityUnits)*BigInt(item.price)+500n)/1000n);}
  function totals(items,discountValue,receivedValue){const subtotal=items.reduce((sum,item)=>sum+lineTotal(item),0);if(!Number.isSafeInteger(subtotal)||subtotal>100000000000000)throw new Error('کۆی پارە لە سنووری ڕێگەپێدراو زیاترە.');const discount=money(discountValue),received=money(receivedValue);if(discount>subtotal)throw new Error('داشکاندن نابێت لە کۆی کاڵاکان زیاتر بێت.');const total=subtotal-discount;return {subtotal,discount,received,total,change:Math.max(0,received-total),remaining:Math.max(0,total-received)};}
  const api={quantityUnits,money,lineTotal,totals};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.SaleMath=api;
})(globalThis);
