'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {normalizeRequest,contentHash,provisionCashier}=require('../access-x/provisioning-core.cjs');
const owner=randomUUID(),requestId=randomUUID();
const makeBody=()=>({request_id:requestId,name:'کاشێری یەکەم',login_email:'Cashier@example.com',permissions:{can_credit:true}});
const token='x'.repeat(64);
function fake(options={}){
 const seen=[],store=new Map();
 const state={authCount:0,attachCount:0,review:0};
 const deps={
  async verifySession(){seen.push('verify');return options.actor||{id:owner};},
  async requirePrimaryManager(){seen.push('manager');return options.manager!==false;},
  async requireFreshAuthentication(){seen.push('reauth');return options.fresh!==false;},
  async reserve({ownerId,requestId,payloadHash}){
   seen.push('reserve');
   const id=ownerId+'/'+requestId;
   if(store.has(id))return store.get(id);
   const slot={state:'new',payloadHash};store.set(id,slot);return slot;
  },
  async claim(){seen.push('claim');return options.claim!==false;},
  async generateTemporaryPassword(){seen.push('password');return 'A'.repeat(36)+'!8';},
  async createAuthUser(){seen.push('createAuth');state.authCount++;if(options.failAt==='auth')throw Error('network ambiguous');return {id:randomUUID()};},
  async recordAuthIdentity(){seen.push('recordAuth');if(options.failAt==='record')throw Error('database down');},
  async attachCashier(p){seen.push('attach');state.attachCount++;assert.equal(p.role,'cashier');if(options.failAt==='attach')throw Error('database down');},
  async markReady({ownerId,requestId,memberId}){seen.push('ready');if(options.failAt==='ready')throw Error('ambiguous commit');const slot=store.get(ownerId+'/'+requestId);slot.state='completed';slot.memberId=memberId;},
  async markForReconciliation({ownerId,requestId}){seen.push('review');state.review++;if(options.failAt==='review')throw Error('cannot persist');store.get(ownerId+'/'+requestId).state='reconciliation';}
 };
 return {deps,seen,state,store};
}
test('normalization is fixed-scope and never accepts client owner, role, password or arbitrary permissions',()=>{
 const q=normalizeRequest(makeBody());
 assert.equal(q.email,'cashier@example.com');
 assert.equal(q.permissions.can_credit,true);
 assert.equal(q.permissions.can_refund,false);
 assert.throws(()=>normalizeRequest({...makeBody(),owner_id:owner}),/invalid_payload/);
 assert.throws(()=>normalizeRequest({...makeBody(),role:'manager'}),/invalid_payload/);
 assert.throws(()=>normalizeRequest({...makeBody(),password:'p'}),/invalid_payload/);
 assert.throws(()=>normalizeRequest({...makeBody(),permissions:{can_discount:true,admin:true}}),/invalid_payload/);
 assert.throws(()=>normalizeRequest({...makeBody(),permissions:{can_discount:'true'}}),/invalid_permissions/);
 assert.throws(()=>normalizeRequest({...makeBody(),login_email:'invalid'}),/invalid_login_email/);
 assert.throws(()=>normalizeRequest({...makeBody(),request_id:'0'}),/invalid_request_id/);
 assert.equal(contentHash(q),contentHash(normalizeRequest({...makeBody(),login_email:'cashier@example.com'})));
});
test('a fully authorized primary manager creates a cashier, with server-generated one-time password',async()=>{
 const f=fake();const v=await provisionCashier(f.deps,{bearerToken:token,body:makeBody()});
 assert.equal(v.status,'created');assert.equal(v.temporaryPassword.length,38);
 assert.equal(f.state.authCount,1);assert.equal(f.state.attachCount,1);
 assert.deepEqual(f.seen,['verify','manager','reauth','reserve','claim','password','createAuth','recordAuth','attach','ready']);
 const replay=await provisionCashier(f.deps,{bearerToken:token,body:makeBody()});
 assert.equal(replay.status,'already_created');assert.equal(replay.temporaryPassword,undefined);
 assert.equal(f.state.authCount,1);
});
test('delegated manager, anonymous actor and stale authentication cannot provision or invoke Auth admin',async()=>{
 for(const options of [{manager:false},{fresh:false},{actor:{id:owner,is_anonymous:true}}]){
  const f=fake(options);
  await assert.rejects(()=>provisionCashier(f.deps,{bearerToken:token,body:makeBody()}));
  assert.equal(f.state.authCount,0);
 }
 const f=fake();await assert.rejects(()=>provisionCashier(f.deps,{bearerToken:'',body:makeBody()}),/unauthorized/);
 assert.equal(f.seen.length,0);
});
test('request conflict, pending reservation and loser of concurrency claim never create a second Auth user',async()=>{
 const f=fake();await provisionCashier(f.deps,{bearerToken:token,body:makeBody()});
 await assert.rejects(()=>provisionCashier(f.deps,{bearerToken:token,body:{...makeBody(),name:'Changed'}}),/request_conflict/);
 assert.equal(f.state.authCount,1);
 const g=fake({claim:false});assert.equal((await provisionCashier(g.deps,{bearerToken:token,body:makeBody()})).status,'pending');
 assert.equal(g.state.authCount,0);
 const h=fake();h.store.set(owner+'/'+requestId,{state:'pending',payloadHash:contentHash(normalizeRequest(makeBody()))});
 assert.equal((await provisionCashier(h.deps,{bearerToken:token,body:makeBody()})).status,'pending');
 assert.equal(h.state.authCount,0);
});
test('ambiguous Auth/DB results enter reconciliation without blind delete or second create attempt',async()=>{
 for(const failAt of ['auth','record','attach','ready']){
  const f=fake({failAt});
  const first=await provisionCashier(f.deps,{bearerToken:token,body:makeBody()});
  assert.equal(first.status,'needs_reconciliation');
  assert.equal(first.temporaryPassword,undefined);
  assert.equal(f.state.review,1);
  const n=f.state.authCount;
  const again=await provisionCashier(f.deps,{bearerToken:token,body:makeBody()});
  assert.equal(again.status,'needs_reconciliation');assert.equal(f.state.authCount,n);
  assert.equal(f.seen.includes('deleteAuthUser'),false);
 }
});
test('failed reconciliation persistence fails closed',async()=>{
 const f=fake({failAt:'review'});
 await assert.rejects(()=>provisionCashier(f.deps,{bearerToken:token,body:makeBody()}),/reconciliation_persistence_failed/);
 assert.equal(f.state.authCount,1);
});
test('missing server adapters are a hard error and cannot silently use browser credentials',async()=>{
 await assert.rejects(()=>provisionCashier({}, {bearerToken:token,body:makeBody()}),/server_adapter_missing/);
});
