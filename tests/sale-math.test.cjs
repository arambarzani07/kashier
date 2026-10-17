const {test}=require('node:test');
const assert=require('node:assert/strict');
const math=require('../sale-math.js');
test('cash change and shortfall have distinct positive values',()=>{
 const items=[{quantityUnits:2000,price:8000},{quantityUnits:1000,price:12000}];
 assert.deepEqual(math.totals(items,'5000','25000'),{subtotal:28000,discount:5000,received:25000,total:23000,change:2000,remaining:0});
 const short=math.totals(items,'5000','15000');assert.equal(short.remaining,8000);assert.equal(short.change,0);
});
test('fractional quantities round once per line to whole IQD',()=>{
 assert.equal(math.quantityUnits('0.125'),125);
 assert.equal(math.lineTotal({quantityUnits:125,price:3000}),375);
 assert.equal(math.lineTotal({quantityUnits:1,price:500}),1);
 assert.equal(math.lineTotal({quantityUnits:1,price:499}),0);
 assert.equal(math.lineTotal({quantityUnits:9999999,price:999999999}),9999998990000);
});
test('invalid money and quantities are rejected',()=>{
 for(const value of ['-1','1.2','','Infinity','1e3','NaN'])assert.throws(()=>math.money(value));
 for(const value of ['0','-1','0.0001','10001','1e2',''])assert.throws(()=>math.quantityUnits(value));
 assert.throws(()=>math.money('1000000001',1000000000));
});
test('discount cannot exceed subtotal; full discount and empty draft are valid',()=>{
 const items=[{quantityUnits:1000,price:1000}];
 assert.throws(()=>math.totals(items,'1001','0'));
 assert.equal(math.totals(items,'1000','0').total,0);
 assert.equal(math.totals([],'0','0').total,0);
});
test('aggregate limit rejects an oversized draft',()=>{
 const item={quantityUnits:10000000,price:1000000000};
 assert.throws(()=>math.totals(Array(11).fill(item),'0','0'));
});
