'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {emailAndPassword,resolveRole,login,createStagedHandler}=require('../access-x/server/login-core.cjs');
const owner=randomUUID(),cashier=randomUUID(),market=randomUUID();
function adapters(opts={}){
 const calls=[];
 const deps={
  authenticate:async({email,password})=>{calls.push('authenticate');return opts.invalidAuth?{}:{accessToken:'verified-token-placeholder-that-is-long'};},
  verifyUser:async()=>{calls.push('verifyUser');return {id:opts.userId||owner,...(opts.user||{})};},
  ownedScopes:async()=>{calls.push('ownedScopes');return opts.owned??[{ownerId:owner,marketId:market,isPrimary:true,enabled:true}];},
  memberships:async()=>{calls.push('memberships');return opts.members??[];},
  credentialPolicy:async()=>{calls.push('credentialPolicy');return opts.policy??{allowed:true,passwordRotated:true,aal:'aal2'};},
  activationRequired:async()=>{calls.push('activationRequired');return opts.activation===true;},
  issueSession:async()=>{calls.push('issueSession');return opts.session??{token:'a'.repeat(44),ttlSeconds:300};},
  rateLimit:async()=>{calls.push('rateLimit');return opts.limit!==false;}
 };
 return {deps,calls};
}
const body={email:'owner@example.com',password:'a long secret'};
function req(data=body,options={}){return {method:options.method||'POST',headers:{origin:options.origin||'https://login.example.test','content-type':options.ctype||'application/json'},body:data};}
function response(){const headers={};return {statusCode:0,headers,payload:'',setHeader(k,v){headers[k]=v;},end(s){this.payload=JSON.parse(s);}};}
test('source inputs never accept owner ID, role, market or redirect',()=>{
 assert.deepEqual(emailAndPassword({email:' Owner@Example.com ',password:'password'}),{email:'owner@example.com',password:'password'});
 for(const k of ['role','ownerId','market_id','next','is_admin','accepted_at']){
  assert.throws(()=>emailAndPassword({...body,[k]:k}),/invalid_credentials/);
 }
 assert.throws(()=>emailAndPassword({email:'bad',password:'pw'}));
 assert.throws(()=>emailAndPassword({email:'owner@example.com',password:''}));
});
test('verified primary owner with single registered market becomes manager, with MFA and rotated password',async()=>{
 const a=adapters(),v=await login(a.deps,body);
 assert.equal(v.role,'manager');assert.equal(v.verified,true);
 assert.ok(a.calls.includes('verifyUser'));assert.ok(a.calls.includes('ownedScopes'));
 assert.deepEqual(a.calls.slice(-2),['credentialPolicy','issueSession']);
});
test('accepted and enabled cashier gets only cashier scope',async()=>{
 const a=adapters({userId:cashier,owned:[],members:[{ownerId:owner,memberId:cashier,marketId:market,role:'cashier',enabled:true,acceptedAt:new Date().toISOString()}],policy:{allowed:true,passwordRotated:true,aal:'aal1'}});
 const v=await login(a.deps,body);assert.equal(v.role,'cashier');
});
test('never promote Auth users to owners without authoritative owner registry',async()=>{
 for(const bad of [
  {owned:[]},{owned:[{ownerId:owner,marketId:market,isPrimary:false,enabled:true}]},
  {owned:[{ownerId:owner,marketId:market,isPrimary:true,enabled:false}]},
  {owned:[{ownerId:owner,marketId:market,isPrimary:true,enabled:true},{ownerId:owner,marketId:randomUUID(),isPrimary:true,enabled:true}]},
  {owned:[{ownerId:cashier,marketId:market,isPrimary:true,enabled:true}]},
  {owned:[{ownerId:owner,marketId:market,isPrimary:true,enabled:true}],members:[{ownerId:cashier,memberId:owner,marketId:randomUUID(),role:'cashier',enabled:true,acceptedAt:'now'}]},
 ]){
  const a=adapters(bad);await assert.rejects(()=>login(a.deps,body),/authorization_denied/);
  assert.equal(a.calls.includes('issueSession'),false);
 }
});
test('cross-market, unaccepted, disabled or delegated-manager membership cannot sign in',async()=>{
 const basic={ownerId:owner,memberId:cashier,marketId:market,role:'cashier',enabled:true,acceptedAt:'2026-10-20'};
 for(const bad of [
  { ...basic,role:'manager'},{...basic,memberId:randomUUID()},
  {...basic,marketId:'not-a-uuid'}, {...basic,enabled:false},
  {...basic,acceptedAt:null},
 ]){
  const a=adapters({userId:cashier,owned:[],members:[bad]});
  await assert.rejects(()=>login(a.deps,body),/authorization_denied/);
  assert.equal(a.calls.includes('issueSession'),false);
 }
 const a=adapters({userId:cashier,owned:[],members:[basic,basic]});
 await assert.rejects(()=>login(a.deps,body),/authorization_denied/);
});
test('pending cashier cannot receive a session even if reset is required',async()=>{
 const a=adapters({userId:cashier,owned:[],members:[{ownerId:owner,memberId:cashier,marketId:market,role:'cashier',enabled:false,acceptedAt:null}],activation:true});
 const v=await login(a.deps,body);assert.equal(v.state,'password_change_required');
 assert.equal(a.calls.includes('issueSession'),false);
});
test('stale auth policy, missing MFA, fraudulent metadata or Auth errors never mint manager session',async()=>{
 for(const opts of [
  {invalidAuth:true},
  {user:{is_anonymous:true}},
  {policy:{allowed:true,passwordRotated:false,aal:'aal2'}},
  {policy:{allowed:true,passwordRotated:true,aal:'aal1'}},
  {policy:{allowed:false,passwordRotated:true,aal:'aal2'}},
  {session:{token:'too-short',ttlSeconds:300}},
  {session:{token:'a'.repeat(44),ttlSeconds:3600}}
 ]){
  const a=adapters(opts);
  await assert.rejects(()=>login(a.deps,body));
 }
 const a=adapters({user:{user_metadata:{role:'manager'}} ,owned:[]});
 await assert.rejects(()=>login(a.deps,body),/authorization_denied/);
});
test('inactive HTTP handler defaults 503 with no Auth calls or cookie',async()=>{
 const a=adapters(),h=createStagedHandler({adapters:a.deps}),res=response();
 await h(req(),res);assert.equal(res.statusCode,503);assert.equal(res.headers['Set-Cookie'],undefined);
 assert.deepEqual(a.calls,[]);
});
test('HTTP adapter cannot turn on without HTTPS origin, rate limiter and trusted auth adapters',()=>{
 assert.throws(()=>createStagedHandler({enabled:true,origin:'http://login.example.test',adapters:adapters().deps}),/invalid_server_origin/);
 assert.throws(()=>createStagedHandler({enabled:true,origin:'https://login.example.test',adapters:{}}),/server_adapter_missing/);
 const a=adapters();delete a.deps.rateLimit;
 assert.throws(()=>createStagedHandler({enabled:true,origin:'https://login.example.test',adapters:a.deps}),/rate_limit_adapter_missing/);
});
test('configured handler sets HttpOnly Secure Strict cookie only after verified manager/role',async()=>{
 const a=adapters(),h=createStagedHandler({enabled:true,origin:'https://login.example.test',adapters:a.deps}),res=response();
 await h(req(),res);assert.equal(res.statusCode,200);
 assert.deepEqual(res.payload,{state:'authenticated',role:'manager',verified:true});
 assert.match(res.headers['Set-Cookie'],/^__Host-kashier_access_x=[a-zA-Z0-9_-]+; Path=\/; Secure; HttpOnly; SameSite=Strict; Max-Age=300$/);
 assert.equal(res.headers['Cache-Control'],'no-store, max-age=0');
 assert.equal(JSON.stringify(res.payload).includes('accessToken'),false);
});
test('origin, payload, content-type and rate-limit guards run before password authentication',async()=>{
 for(const r of [
  req(body,{origin:'https://malicious.example'}),
  req(body,{ctype:'text/plain'}),
  req(body,{method:'GET'}),
  req({...body,comment:'x'.repeat(4200)})
 ]){
  const a=adapters(),h=createStagedHandler({enabled:true,origin:'https://login.example.test',adapters:a.deps}),res=response();
  await h(r,res);assert.ok([403,415,405,400].includes(res.statusCode));assert.deepEqual(a.calls,[]);
 }
 const a=adapters({limit:false}),h=createStagedHandler({enabled:true,origin:'https://login.example.test',adapters:a.deps}),res=response();
 await h(req(),res);assert.equal(res.statusCode,429);assert.deepEqual(a.calls,['rateLimit']);
});
test('invalid credentials or unauthorized role return generic error and no cookie',async()=>{
 for(const opts of [{invalidAuth:true},{owned:[]},{policy:{allowed:false,passwordRotated:false}},{session:{token:'too-short',ttlSeconds:300}}]){
  const a=adapters(opts),h=createStagedHandler({enabled:true,origin:'https://login.example.test',adapters:a.deps}),res=response();
  await h(req(),res);assert.equal(res.statusCode,401);assert.deepEqual(res.payload,{state:'unavailable'});
  assert.equal(res.headers['Set-Cookie'],undefined);
 }
});
