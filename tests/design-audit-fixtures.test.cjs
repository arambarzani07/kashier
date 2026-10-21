'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const F=require('./fixtures/design-data.cjs');

test('populated UI fixtures reconcile through the real report validators',()=>{
 for(const [rpc,module] of [['get_sales_product_report','sales-report-math'],['get_purchase_report','purchase-report-math'],['get_cash_statement','cash-statement-math']]){
  const data=F.rpc(rpc);
  assert.doesNotThrow(()=>require('../'+module+'.js').validate(data,data.from,data.to));
 }
 for(const kind of ['customer','supplier']){
  const data=F.rpc('get_'+kind+'_balances_report');
  assert.doesNotThrow(()=>require('../customer-balances-model.js').validate(data,'',true,kind));
 }
 const profile=F.rpc('get_product_profile',{p_product:F.owner});
 assert.doesNotThrow(()=>require('../product-profile-model.js').validate(profile,F.owner,0));
});

test('UI lookup fixtures preserve count headers, exact IDs and valid long text',()=>{
 const all=F.response(new URL('https://fixture.invalid/rest/v1/products'));
 assert.equal(all.data.length,50);
 assert.equal(all.headers['content-range'],'0-49/50');
 const one=F.response(new URL('https://fixture.invalid/rest/v1/products?id=in.('+F.products[0].id+')'));
 assert.equal(one.data.length,1);
 assert.equal(one.data[0].id,F.products[0].id);
 assert.ok(F.products.every(p=>p.name.length<=150&&p.barcode.length<=64));
 assert.ok(F.people.every(p=>p.name.length<=100));
});

test('UI fixture adapter rejects mutations and unknown data sources',()=>{
 for(const name of ['post_cash_sale','post_debt_entry','import_products','unknown_rpc'])assert.throws(()=>F.rpc(name),/No read-only UI fixture/);
 assert.throws(()=>F.response(new URL('https://fixture.invalid/rest/v1/private_data')),/No read-only UI fixture/);
});
