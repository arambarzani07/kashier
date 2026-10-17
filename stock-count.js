(function(root){'use strict';
const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
function units(value){const m=/^(\d{1,10})(?:\.(\d{1,3}))?$/.exec(String(value).trim());if(!m)throw Error('بڕێکی سفر یان زیاتر بنووسە؛ تا سێ خانەی دەیی.');const n=Number(m[1])*1000+Number((m[2]||'').padEnd(3,'0'));if(!Number.isSafeInteger(n)||n>1000000000000)throw Error('بڕی ژماردن زۆر گەورەیە.');return n;}
function valid(journal,product){const p=journal?.payload;return journal?.version===1&&uuid(p?.p_id)&&p.p_product===product&&uuid(product)&&Number.isSafeInteger(p.p_expected_units)&&p.p_expected_units>=0&&p.p_expected_units<=1e12&&Number.isSafeInteger(p.p_counted_units)&&p.p_counted_units>=0&&p.p_counted_units<=1e12&&typeof p.p_expected_version==='string'&&/^\d{1,19}$/.test(p.p_expected_version)&&BigInt(p.p_expected_version)<=9223372036854775807n&&typeof p.p_note==='string'&&p.p_note.trim().length>0&&p.p_note.length<=500&&typeof journal.name==='string';}
root.StockCount={units,valid,uuid};if(typeof module==='object'&&module.exports)module.exports=root.StockCount;
})(globalThis);
