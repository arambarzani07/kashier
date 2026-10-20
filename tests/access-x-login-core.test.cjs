'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {handleLogin,authorityOf,parseCredentials}=require('../access-x/login-core.cjs');
const {createSupabasePasswordAdapter}=require('../access-x/supabase-password-adapter.cjs');
const USER='90000000-0000-4000-8000-000000000001';
const OWNER='90000000-0000-4000-8000-000000000002';
function baseDeps(o={}){
 const calls=[];
 return {calls,deps:{
  releaseGate:true,expectedOrigin:'https://market.example',
  async rateLimit(...a){calls.push('rate');return o.limit??true;},
  async authenticatePassword(){calls.push('auth');return Object.prototype.hasOwnProperty.call(o,'auth')?o.auth:{accessToken:'t'.repeat(100)};},
  async verifyUser(){calls.push('verify');return o.user??{id:USER};},
  async resolveAuthority(){calls.push('authority');return o.proof??{source:'primary_owner_database',role:'manager',active:true,ownerId:USER,marketApproved:true};},
  async createSession(){calls.push('session');return o.session??{opaqueId:'a'.repeat(64)};},
  ...o.overrides
 }};
}
function request(body={email:'owner@example.com',password:'unshared-synthetic-password'},headers={}){
 return {method:'POST',headers:{origin:'https://market.example','content-type':'application/json',...headers},body:JSON.stringify(body),clientIp:'192.0.2.9'};
}
const result=(o)=>JSON.parse(o.body);
test('disabled staging returns 503 without invoking providers or generating cookies',async()=>{
 const f=baseDeps();f.deps.releaseGate=false;
 const r=await handleLogin(request(),f.deps);
 assert.equal(r.status,503);assert.deepEqual(f.calls,[]);
 assert.equal(r.headers['Set-Cookie'],undefined);assert.equal(result(r).state,'unavailable');
});
test('requires complete gated server contract',async()=>{
 const f=baseDeps();delete f.deps.rateLimit;
 assert.equal((await handleLogin(request(),f.deps)).status,503);
 const v=baseDeps();v.deps.expectedOrigin='http://market.example';
 assert.equal((await handleLogin(request(),v.deps)).status,503);
});
test('rejects cross-origin requests, wrong methods, content type, giant bodies and invalid JSON before auth',async()=>{
 const f=baseDeps();
 for(const q of [
  {...request(),method:'GET'},request({}, {origin:'https://evil.example'}),
  request({}, {'sec-fetch-site':'cross-site'}),request({}, {'content-type':'text/plain'}),
  {...request(),body:' '.repeat(5000)},{...request(),body:'{invalid'}
 ]){const x=await handleLogin(q,f.deps);assert.ok(x.status>=400);assert.equal(x.headers['Set-Cookie'],undefined);}
 assert.deepEqual(f.calls,[]);
});
test('strictly rejects password, owner_id and role injection',()=>{
 assert.equal(parseCredentials('bad'),null);
 assert.equal(parseCredentials(JSON.stringify({email:'a@b.com',password:'pw',role:'manager'})),null);
 assert.equal(parseCredentials(JSON.stringify({email:'a@b.com',password:'pw',owner_id:USER})),null);
 assert.equal(parseCredentials(JSON.stringify({email:'a@b.com',password:''})),null);
 assert.equal(parseCredentials(JSON.stringify({email:'a@b.com',password:'pw'})).email,'a@b.com');
});
test('requires durable rate limiting before Auth provider is called',async()=>{
 const f=baseDeps({limit:false});const r=await handleLogin(request(),f.deps);
 assert.equal(r.status,429);assert.deepEqual(f.calls,['rate']);
 assert.ok(!r.body.includes('owner@example.com'));
});
test('generic denial for failed credentials and missing or anonymous identity',async()=>{
 for(const opt of [{auth:null},{auth:{}},{user:{id:USER,is_anonymous:true}},{user:{id:'untrusted'}}]){
  const f=baseDeps(opt),r=await handleLogin(request(),f.deps);
  assert.equal(r.status,401);assert.equal(result(r).state,'invalid_credentials');assert.equal(r.headers['Set-Cookie'],undefined);
 }
});
test('owner requires explicit authoritative primary-owner database proof; cannot infer owner from Supabase signup',async()=>{
 for(const proof of [
  {source:'user_metadata',role:'manager',ownerId:USER,active:true,marketApproved:true},
  {source:'primary_owner_database',role:'manager',ownerId:OWNER,active:true,marketApproved:true},
  {source:'primary_owner_database',role:'manager',ownerId:USER,active:true,marketApproved:false},
  {source:'cashier_membership_database',role:'manager',ownerId:OWNER,memberId:USER,enabled:true,accepted:true,marketApproved:true,uniqueMarket:true,passwordRotated:true}
 ]){const f=baseDeps({proof});const r=await handleLogin(request(),f.deps);assert.equal(r.status,401);assert.ok(!f.calls.includes('session'));}
});
test('cashier requires enabled, accepted, unique market and changed password',async()=>{
 const base={source:'cashier_membership_database',role:'cashier',ownerId:OWNER,memberId:USER,enabled:true,accepted:true,marketApproved:true,uniqueMarket:true,passwordRotated:true};
 for(const change of [{enabled:false},{accepted:false},{uniqueMarket:false},{passwordRotated:false},{memberId:OWNER}]){
  const f=baseDeps({proof:{...base,...change}}),r=await handleLogin(request(),f.deps);
  assert.notEqual(result(r).state,'authenticated');assert.equal(r.headers['Set-Cookie'],undefined);
 }
 const f=baseDeps({proof:base}),r=await handleLogin(request(),f.deps);
 assert.equal(r.status,200);assert.deepEqual(result(r),{state:'authenticated',verified:true,role:'cashier'});
 assert.match(r.headers['Set-Cookie'],/^__Host-ax_sid=[A-Za-z0-9_-]{43,128}; Path=\/; HttpOnly; Secure; SameSite=Strict; Max-Age=28800$/);
 assert.deepEqual(f.calls,['rate','auth','verify','authority','session']);
});
test('staged cashier is not activated or issued cookie until credential rotation',async()=>{
 const proof={source:'cashier_membership_database',role:'cashier',ownerId:OWNER,memberId:USER,enabled:false,accepted:false,passwordRotated:false};
 const f=baseDeps({proof}),r=await handleLogin(request(),f.deps);
 assert.equal(r.status,200);assert.equal(result(r).state,'password_change_required');
 assert.equal(r.headers['Set-Cookie'],undefined);assert.ok(!f.calls.includes('session'));
});
test('manager session response is opaque with secure cookie and excludes tokens or IDs',async()=>{
 const f=baseDeps(),r=await handleLogin(request(),f.deps);
 assert.equal(r.status,200);assert.deepEqual(result(r),{state:'authenticated',verified:true,role:'manager'});
 assert.equal(r.headers['Cache-Control'],'no-store, private, max-age=0');
 assert.equal(r.headers['X-Content-Type-Options'],'nosniff');
 assert.ok(!r.body.includes(USER)&&!r.body.includes('owner@example.com'));
 assert.equal(r.headers['Set-Cookie'].includes('tttt'),false);
});
test('session service cannot force insecure, forged or low-entropy cookie',async()=>{
 for(const x of ['short','x; Path=/; Secure','a'.repeat(42),undefined]){
  const f=baseDeps({session:{opaqueId:x}}),r=await handleLogin(request(),f.deps);
  assert.equal(r.status,503);assert.equal(r.headers['Set-Cookie'],undefined);
 }
});
test('errors from providers are sanitized without revealing identity, password or token',async()=>{
 const f=baseDeps({overrides:{async authenticatePassword(){throw Error('secret-token-password-contents')}}});
 const r=await handleLogin(request(),f.deps);
 assert.equal(r.status,503);assert.equal(r.body.includes('secret'),false);assert.equal(r.headers['Set-Cookie'],undefined);
});
test('Supabase Auth adapter allows only HTTPS URL and public key, not service key',()=>{
 const cfg={supabaseUrl:'https://project.supabase.co/',publishableKey:'sb_publishable_test',fetchImpl:async()=>{}};
 assert.ok(createSupabasePasswordAdapter(cfg));
 assert.throws(()=>createSupabasePasswordAdapter({...cfg,supabaseUrl:'http://project.supabase.co/'}));
 assert.throws(()=>createSupabasePasswordAdapter({...cfg,publishableKey:'sb_secret_leaked'}));
});
test('provider adapter calls password token endpoint then user API with bearer token',async()=>{
 const calls=[];
 const provider=createSupabasePasswordAdapter({supabaseUrl:'https://project.supabase.co/',publishableKey:'sb_publishable_test',
  fetchImpl:async(url,options)=>{calls.push({url,options});return {ok:true,json:async()=>url.includes('grant_type')?{access_token:'x'.repeat(60)}:{id:USER}};}});
 const r=await provider.authenticatePassword({email:'owner@example.com',password:'demo-password'});
 assert.equal(r.accessToken.length,60);
 assert.deepEqual(await provider.verifyUser(r),{id:USER,is_anonymous:false});
 assert.equal(calls[0].url,'https://project.supabase.co/auth/v1/token?grant_type=password');
 assert.equal(calls[1].url,'https://project.supabase.co/auth/v1/user');
 assert.equal(calls[1].options.headers.Authorization,'Bearer '+'x'.repeat(60));
 assert.equal(calls[0].options.redirect,'error');assert.equal(calls[0].options.cache,'no-store');
});