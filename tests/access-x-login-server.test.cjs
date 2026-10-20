'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {Readable}=require('node:stream');
const {randomUUID}=require('node:crypto');
const fs=require('node:fs'),path=require('node:path');
const {authenticateAccessX,assessAccess,cleanCredentials}=require('../access-x/server/login-service.cjs');
const {createLoginHandler}=require('../access-x/server/login-handler.cjs');
const {createSupabasePasswordAuth}=require('../access-x/server/supabase-password-auth.cjs');
const root=path.resolve(__dirname,'..'),uid=randomUUID(),market=randomUUID(),other=randomUUID();
const email='cashier@example.invalid',secret='not a real password';
function fake(role='cashier',overrides={}){
 const calls=[],id=overrides.userId||uid;
 const d={
  async checkRateLimit(x){calls.push(['rate',x]);return overrides.rate===undefined?true:overrides.rate;},
  async passwordSignIn(e,p){calls.push(['auth',e,p]);if(overrides.failAuth)throw Object.assign(Error('bad'),{code:'invalid_credentials'});return {user:{id},access_token:'sample-token-at-least-20-characters'};},
  async verifyUser(t){calls.push(['verify',t]);return {id:overrides.verifyId||id,is_anonymous:overrides.anonymous||false};},
  async resolveAccess(id){calls.push(['role',id]);if(overrides.roleInfo)return overrides.roleInfo;
   return role==='manager'?{state:'active',role:'manager',userId:id,ownerId:id,primaryOwner:true,verifiedByDatabase:true}:
     {state:'active',role:'cashier',userId:id,ownerId:market,enabled:true,accepted:true,credentialRotationComplete:true,membershipsCount:1,verifiedByDatabase:true};},
  async commitSession(o){calls.push(['commit',o]);return overrides.commit===undefined?true:overrides.commit;}
 };
 return {d,calls};
}
function httpReq(body,{headers={},method='POST',ip='192.0.2.7'}={}){
 return Object.assign(Readable.from([JSON.stringify(body)]),{
  method,trustedClientIp:ip,headers:{
   origin:'https://test.kashier.invalid','content-type':'application/json','user-agent':'AccessXRegression',
   'sec-fetch-site':'same-origin',...headers
  }
 });
}
function res(){
 const headers={};return {
  statusCode:0,headers,
  setHeader(n,v){headers[n.toLowerCase()]=v;},
  end(payload){this.body=JSON.parse(payload);}
 };
}
const factory=d=>createLoginHandler(d,{allowedOrigin:'https://test.kashier.invalid'});
const data={email,password:secret};
test('manager and cashier authorization never comes from form role or metadata',async()=>{
 const mgr=fake('manager'),cs=fake('cashier');
 const a=await authenticateAccessX(mgr.d,data,{ip:'192.0.2.1',userAgent:'test'});
 const b=await authenticateAccessX(cs.d,data,{ip:'192.0.2.1',userAgent:'test'});
 assert.equal(a.role,'manager');assert.equal(b.role,'cashier');
 assert.equal(a.sessionSecret.length>=40,true);assert.notEqual(a.sessionSecret,b.sessionSecret);
 assert.equal(mgr.calls.at(-1)[1].ownerId,uid);
 assert.equal(cs.calls.at(-1)[1].ownerId,market);
 assert.equal(cs.calls.at(-1)[1].tokenHash.length,64);
 assert.equal(cs.calls.at(-1)[1].expiresInSeconds,600);
 assert.equal(JSON.stringify(cs.calls.at(-1)).includes(b.sessionSecret),false);
 assert.throws(()=>cleanCredentials({...data,role:'manager'}),/invalid_request/);
 assert.throws(()=>cleanCredentials({...data,owner_id:other}),/invalid_request/);
 assert.throws(()=>cleanCredentials({...data,permissions:{staff:true}}),/invalid_request/);
});
test('active staff must have exactly one verified enabled accepted membership and completed credential rotation',async()=>{
 const base={state:'active',role:'cashier',userId:uid,ownerId:market,enabled:true,accepted:true,credentialRotationComplete:true,membershipsCount:1,verifiedByDatabase:true};
 assert.equal(assessAccess({id:uid},base).role,'cashier');
 for(const patch of [{enabled:false},{accepted:false},{credentialRotationComplete:false},{membershipsCount:2},
  {verifiedByDatabase:false},{ownerId:uid},{userId:other},{role:'manager'}]){
  const a=fake('cashier',{roleInfo:{...base,...patch}});
  await assert.rejects(()=>authenticateAccessX(a.d,data,{ip:'192.0.2.1',userAgent:'test'}),/invalid_credentials/);
  assert.equal(a.calls.some(x=>x[0]==='commit'),false);
 }
});
test('pending first-login changes cannot create an active HTTP session',async()=>{
 const a=fake('cashier',{roleInfo:{state:'password_change_required',role:'cashier',userId:uid,ownerId:market,
  provisioned:true,enabled:false,credentialRotationPending:true}});
 const req=httpReq(data),response=res();
 await factory(a.d)(req,response);
 assert.equal(response.statusCode,200);
 assert.equal(response.body.state,'password_change_required');
 assert.equal(response.headers['set-cookie'],undefined);
 assert.equal(a.calls.some(x=>x[0]==='commit'),false);
});
test('anonymous, mismatched auth user or unconfigured dependency fail without a cookie',async()=>{
 for(const options of [{anonymous:true},{verifyId:other}]){
  const a=fake('cashier',options),response=res();await factory(a.d)(httpReq(data),response);
  assert.equal(response.statusCode,401);assert.equal(response.headers['set-cookie'],undefined);
 }
 const response=res();await factory({})(httpReq(data),response);
 assert.equal(response.statusCode,503);
});
test('same-origin POST with verified role returns only a server opaque httpOnly cookie',async()=>{
 const a=fake('manager'),response=res();await factory(a.d)(httpReq(data),response);
 assert.equal(response.statusCode,200);
 assert.equal(response.body.role,'manager');assert.equal(response.body.verified,true);
 assert.equal(response.body.state,'authenticated');
 assert.equal(JSON.stringify(response.body).includes(secret),false);
 assert.match(response.headers['set-cookie'],/^__Host-kashier_ax=[\w-]+; Path=\/; Secure; HttpOnly; SameSite=Strict; Max-Age=600$/);
 assert.equal(response.headers['cache-control'],'no-store, private');
 assert.equal(response.headers['x-content-type-options'],'nosniff');
 assert.equal(a.calls.filter(x=>x[0]==='commit').length,1);
});
test('HTTP handler rejects cross-origin, invalid content type, non-POST and oversized body BEFORE authentication',async()=>{
 const a=fake();
 for(const [opts,code] of [
  [{method:'GET'},405],[{headers:{origin:'https://evil.invalid'}},403],
  [{headers:{'sec-fetch-site':'cross-site'}},403],
  [{headers:{'content-type':'text/plain'}},415],
  [{headers:{'content-length':'3000'}},413]
 ]){
  const response=res();await factory(a.d)(httpReq(data,opts),response);
  assert.equal(response.statusCode,code);
  assert.equal(response.headers['set-cookie'],undefined);
 }
 const req=httpReq(data);req.body={email,password:'x'.repeat(2200)};
 const response=res();await factory(a.d)(req,response);assert.equal(response.statusCode,413);
 assert.equal(a.calls.length,0);
});
test('no rate limiter permission or durable session store means fail closed',async()=>{
 for(const opt of [{rate:false,code:429},{rate:'unknown',code:503},{commit:false,code:503},{failAuth:true,code:401}]){
  const a=fake('cashier',opt),response=res();await factory(a.d)(httpReq(data),response);
  assert.equal(response.statusCode,opt.code);
  assert.equal(response.headers['set-cookie'],undefined);
 }
 const a=fake('manager'),response=res();await factory(a.d)(httpReq(data,{ip:''}),response);
 assert.equal(response.statusCode,503);
});
test('GoTrue HTTP adapter checks password token and revalidates account using /user',async()=>{
 const calls=[];const api=createSupabasePasswordAuth({
  supabaseUrl:'https://example.supabase.co',publishableKey:'public-test-key',
  fetchImpl:async(url,options)=>{
   calls.push({url,options});
   return {ok:true,status:200,json:async()=>url.includes('/token')?{user:{id:uid},access_token:'sample-token-at-least-20-characters'}:{id:uid}};
  }
 });
 const auth=await api.passwordSignIn(email,secret);
 const u=await api.verifyUser(auth.access_token);
 assert.equal(u.id,uid);assert.equal(calls.length,2);
 assert.match(calls[0].url,/\/auth\/v1\/token\?grant_type=password$/);
 assert.equal(calls[0].options.method,'POST');
 assert.equal(calls[1].options.headers.Authorization,'Bearer '+auth.access_token);
 assert.equal(calls[0].options.headers.apikey,'public-test-key');
 assert.equal(calls[0].options.redirect,'error');
 assert.equal(calls[1].options.redirect,'error');
 assert.throws(()=>createSupabasePasswordAuth({supabaseUrl:'http://evil.invalid',publishableKey:'x'}),/unavailable/);
});
test('staged login core is not deployed as API route; maintenance routing is still fail closed',()=>{
 assert.equal(fs.existsSync(path.join(root,'api/access-x/login.js')),false);
 const v=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));
 assert.equal(v.routes[0].dest,'/maintenance.html');
 const source=fs.readFileSync(path.join(root,'access-x/server/login-service.cjs'),'utf8');
 assert.doesNotMatch(source,/user_metadata|raw_user_meta_data|service_role|KashierData\.signIn/);
});
