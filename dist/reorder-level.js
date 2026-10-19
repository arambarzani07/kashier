(function(root){'use strict';
function parse(value){if(typeof value!=='string')throw Error('سنووری کۆگا نادروستە.');const text=value.trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776));if(!text)return null;const m=/^(\d{1,10})(?:\.(\d{1,3}))?$/.exec(text);if(!m)throw Error('سنوور دەبێت سفر یان زیاتر بێت، تا سێ خانەی دەیی؛ بەبێ کۆما.');const n=BigInt(m[1])*1000n+BigInt((m[2]||'').padEnd(3,'0'));if(n>1000000000000n)throw Error('سنوور نابێت لە 1,000,000,000 زیاتر بێت.');return Number(n);}
function format(value){if(value===null||value===undefined)return '';if(!Number.isSafeInteger(value)||value<0||value>1000000000000)throw Error('سنووری کۆگا نادروستە.');const part=String(value%1000).padStart(3,'0').replace(/0+$/,'');return Math.floor(value/1000)+(part?'.'+part:'');}
root.ReorderLevel={parse,format};if(typeof module==='object'&&module.exports)module.exports=root.ReorderLevel;
})(globalThis);
