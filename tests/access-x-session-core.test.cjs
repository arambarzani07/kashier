'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {createSessionManager,hashToken,parseSessionCookie}=require('../access-x/server/session-core.cjs');
const owner=randomUUID(),cashier=randomUUID(),market=randomUUID(),scope={role:'cashier',ownerId:owner,marketId:market};
function fake({time=1700000000000,allowed=true,ttlSeconds=600,random}={}){
 const rows=new Map(),ops=[],state={time,allowed};
 const store={
  async insert(row){ops.push('insert');if(rows.has(row.tokenHash))return false;rows.set(row.tokenHash,{...row,revokedAt:null});return true;},
  async get(hash){ops.push('get');return rows.get(hash);},
  async revoke(hash){ops.push('revoke');if(!rows.has(hash))return false;rows.get(hash).revokedAt=state.time;return true;}
 };
 const deps={store,requireCurrentAccess:async()=>{ops.push('authorize');return state.allowed;},clock:()=>state.time,ttlSeconds};
 if(random)deps.random=random;
 const mgr=createSessionManager(deps);
 return {mgr,rows,ops,state};
}
function cookie(token){return '__Host-kashier_access_x='+token;}
test('session tokens have 256 bits entropy and only SHA-256 digests enter durable store',async()=>{
 const f=fake(),s=await f.mgr.issueSession({userId:cashier,scope});
 assert.match(s.token,/^[A-Za-z0-9_-]{43}$/);assert.equal(s.ttlSeconds,600);
 const rows=[...f.rows.values()];assert.equal(rows.length,1);
 assert.equal(rows[0].tokenHash,hashToken(s.token));
 assert.equal(rows[0].tokenHash.length,64);
 assert.equal(JSON.stringify(rows).includes(s.token),false);
 assert.equal(rows[0].ownerId,owner);
 assert.equal(rows[0].marketId,market);
 assert.equal(rows[0].role,'cashier');
 assert.equal(rows[0].expiresAt-f.state.time,600000);
});
test('owner and cashier sessions are scoped and manager cannot impersonate owner via another UUID',async()=>{
 const f=fake();
 const s=await f.mgr.issueSession({userId:owner,scope:{role:'manager',ownerId:owner,marketId:market}});
 const v=await f.mgr.verifySession(cookie(s.token));
 assert.deepEqual(v,{userId:owner,role:'manager',ownerId:owner,marketId:market});
 await assert.rejects(()=>f.mgr.issueSession({userId:cashier,scope:{role:'manager',ownerId:owner,marketId:market}}));
 await assert.rejects(()=>f.mgr.issueSession({userId:owner,scope:{role:'cashier',ownerId:owner,marketId:market}}));
});
test('current staff revocation is enforced upon EVERY session verification, not issuance only',async()=>{
 const f=fake(),s=await f.mgr.issueSession({userId:cashier,scope});
 assert.equal((await f.mgr.verifySession(cookie(s.token))).role,'cashier');
 f.state.allowed=false;
 assert.equal(await f.mgr.verifySession(cookie(s.token)),null);
 assert.equal(f.rows.get(hashToken(s.token)).revokedAt,f.state.time);
 assert.deepEqual(f.ops,['insert','get','authorize','get','authorize','revoke']);
});
test('session expiration, explicit signout and revoked cookie deny access',async()=>{
 const f=fake(),s=await f.mgr.issueSession({userId:cashier,scope});
 f.state.time+=600000;
 assert.equal(await f.mgr.verifySession(cookie(s.token)),null);
 const g=fake(),t=await g.mgr.issueSession({userId:cashier,scope});
 assert.equal(await g.mgr.revokeSession(cookie(t.token)),true);
 assert.equal(await g.mgr.verifySession(cookie(t.token)),null);
});
test('duplicate, malformed and cookie injection are rejected',()=>{
 const token='A'.repeat(43);
 assert.equal(parseSessionCookie('hello=1; '+cookie(token)),token);
 for(const bad of ['',cookie(token)+'; '+cookie(token),cookie('a; evil=1'),cookie('!'.repeat(43)),cookie('short'),123]){
  assert.equal(parseSessionCookie(bad),null);
 }
 assert.throws(()=>hashToken('short'));
});
test('store must be truly backed by supplied adapters; no default in-memory or passive acceptance',()=>{
 assert.throws(()=>createSessionManager({}));
 assert.throws(()=>createSessionManager({store:{get:async()=>{}},requireCurrentAccess:async()=>true}));
 assert.throws(()=>createSessionManager({...fake().mgr,ttlSeconds:901}));
});
test('storage outage, corrupted scope and denied reauthorization never grant access',async()=>{
 const f=fake(),s=await f.mgr.issueSession({userId:cashier,scope});
 f.rows.get(hashToken(s.token)).marketId='invalid';
 assert.equal(await f.mgr.verifySession(cookie(s.token)),null);
 const g=fake(),t=await g.mgr.issueSession({userId:cashier,scope});
 g.rows.get(hashToken(t.token)).expiresAt=g.state.time+910000;
 assert.equal(await g.mgr.verifySession(cookie(t.token)),null);
});
test('cryptographic entropy failure is fatal before any insert',async()=>{
 const f=fake({random:()=>Buffer.from('short')});
 await assert.rejects(()=>f.mgr.issueSession({userId:cashier,scope}),/access_x_session_denied/);
 assert.equal(f.rows.size,0);
});
test('no service key, cookie secret or backing DB credentials are committed in source',()=>{
 const fs=require('node:fs'),path=require('node:path');
 const text=fs.readFileSync(path.resolve(__dirname,'../access-x/server/session-core.cjs'),'utf8');
 assert.doesNotMatch(text,/SUPABASE_SERVICE_ROLE|sb_secret_|localStorage|sessionStorage/);
 assert.doesNotMatch(text,/console\.(?:log|error)|process\.env/);
});
