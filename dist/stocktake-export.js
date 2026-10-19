(function(root){'use strict';
function quantity(units){if(!Number.isSafeInteger(units)||units<0)throw Error('بڕی کۆگا نادروستە.');const whole=Math.floor(units/1000),fraction=String(units%1000).padStart(3,'0').replace(/0+$/,'');return String(whole)+(fraction?'.'+fraction:'');}
function cell(value){let text=String(value??'');if(/^[\s\u0000-\u0020]*[=+@-]/.test(text)||/^[\t\r\n]/.test(text))text="'"+text;return '"'+text.replace(/"/g,'""')+'"';}
function csv(snapshot){const lines=[['کاتی ئامادەکردن','گەڕان','ناسنامەی کاڵا','ناوی کاڵا','بارکۆد','بڕی تۆمارکراو','ژماردنی ڕاستەقینە','تێبینی'],...snapshot.rows.map(p=>[snapshot.generated_at,snapshot.query,p.id,p.name,p.barcode,quantity(p.quantity_units),'',''])];return '\ufeff'+lines.map(row=>row.map(cell).join(',')).join('\r\n')+'\r\n';}
root.StocktakeExport={quantity,cell,csv};if(typeof module==='object'&&module.exports)module.exports=root.StocktakeExport;
})(globalThis);
