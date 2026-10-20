'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {createSupabaseAuthTransport}=require('../access-x/server/supabase-auth-transport.cjs');
const url='https://dhfyqxdfwhxlipbsasqf.supabase.co';
const anon='sb_publishable_local-test-key-only-123456789';
const identity=randomUUID();
function json(body,{status=200,kind='application/json',length}={}){
 const raw=typeof body==='string'?body:JSON.stringify(body);
 return {ok:status>=200&&status<300,status,
  headers:{get:n=>n==='content-type'?kind:n==='content-length'?(length??String(Buffer.byteLength(raw))):null},
  text:async()=>raw};
}
function simulate(handler){
 const calls=[];
 const fetchImpl=async(url,options)=>{calls.push({url,options});return handler(url,options)};
 return {transport:createSupabaseAuthTransport({projectUrl:url,anonKey:anon,fetchImpl}),calls};
}
test('strict Supabase project URL and publishable key configuration',()=>{
 for(const projectUrl of ['http://dhfyqxdfwhxlipbsasqf.supabase.co',url+'/rest/v1',
  'https://attacker.example',url+'?next=evil','https://u:p@dhfyqxdfwhxlipbsasqf.supabase.co',
  'https://dhfyqxdfwhxlipbsasqf.supabase.co:8443']){
  assert.throws(()=>createSupabaseAuthTransport({projectUrl,anonKey:anon}),/access_x_auth_unavailable/);
 }
 for(const anonKey of ['sb_secret_abcdef0123456789','service_role','',undefined]){
  assert.throws(()=>createSupabaseAuthTransport({projectUrl:url,anonKey}),/access_x_auth_unavailable/);
 }
 assert.throws(()=>createSupabaseAuthTransport({projectUrl:url,anonKey:anon,timeoutMs:20000}));
});
test('legacy JWT config accepts only role anon; service_role is rejected',()=>{
 const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
 const anonJWT=[enc({alg:'HS256',typ:'JWT'}),enc({role:'anon'}),'sig'].join('.');
 const serviceJWT=[enc({alg:'HS256'}),enc({role:'service_role'}),'sig'].join('.');
 assert.doesNotThrow(()=>createSupabaseAuthTransport({projectUrl:url,anonKey:anonJWT}));
 assert.throws(()=>createSupabaseAuthTransport({projectUrl:url,anonKey:serviceJWT}),/access_x_auth_unavailable/);
});
test('real Auth token endpoint and verification endpoint are separate fixed same-host requests',async()=>{
 const token='eyJhbGciOiJIUzI1NiJ9.'+'a'.repeat(28)+'.'+'b'.repeat(30);
 const e=simulate((where,options)=>{
  if(where.endsWith('grant_type=password'))return json({access_token:token,token_type:'bearer',refresh_token:'NOT-FOR-CLIENT'});
  if(where.endsWith('/auth/v1/user'))return json({id:identity,is_anonymous:false,user_metadata:{role:'manager'}});
  throw Error('unexpected path');
 });
 const r=await e.transport.authenticate({email:'test@example.org',password:'secretvalue'});
 assert.deepEqual(r,{accessToken:token});
 const u=await e.transport.verifyUser(r.accessToken);
 assert.deepEqual(u,{id:identity,is_anonymous:false});
 assert.equal(e.calls.length,2);
 assert.equal(e.calls[0].url,url+'/auth/v1/token?grant_type=password');
 assert.equal(e.calls[0].options.method,'POST');
 assert.deepEqual(JSON.parse(e.calls[0].options.body),{email:'test@example.org',password:'secretvalue'});
 assert.equal(e.calls[0].options.headers.apikey,anon);
 assert.equal(e.calls[0].options.headers.Authorization,undefined);
 assert.equal(e.calls[1].url,url+'/auth/v1/user');
 assert.equal(e.calls[1].options.method,'GET');
 assert.equal(e.calls[1].options.headers.Authorization,'Bearer '+token);
 for(const call of e.calls){
  assert.equal(call.options.redirect,'error');assert.equal(call.options.credentials,'omit');
  assert.equal(call.options.cache,'no-store');assert.ok(call.options.signal);
 }
});
test('failed/redirected or malformed upstream results deny without leaking payload details',async()=>{
 const cases=[
  json({msg:'account missing'}, {status:401}),
  json({access_token:'short',token_type:'bearer'}),
  json({access_token:'a'.repeat(25),token_type:'unknown'}),
  json('bad json',{kind:'text/html'}),
  json('x'.repeat(40000),{length:'40000'}),
  {ok:true,status:200,headers:{get:()=> 'application/json'},text:async()=>'{oops'}
 ];
 for(const sample of cases){
  const e=simulate(()=>sample);
  await assert.rejects(()=>e.transport.authenticate({email:'a@b.co',password:'the-hidden-password'}),err=>
   err.message==='access_x_auth_unavailable'&&!err.message.includes('the-hidden-password'));
 }
});
test('verification never reads unverifiable JSON user metadata or accepts anonymous/invalid account identifiers',async()=>{
 const e=simulate(()=>json({id:'not-a-uuid',user_metadata:{role:'manager'}}));
 await assert.rejects(()=>e.transport.verifyUser('a'.repeat(40)),/access_x_auth_unavailable/);
 const f=simulate(()=>json({id:identity,is_anonymous:true,user_metadata:{role:'owner'}}));
 assert.deepEqual(await f.transport.verifyUser('a'.repeat(40)),{id:identity,is_anonymous:true});
 await assert.rejects(()=>f.transport.verifyUser('bad token'),/access_x_auth_unavailable/);
});
test('upstream transport failure is a generic denial without logging private credentials',async()=>{
 const e=simulate(()=>{throw Error('network error: secret password and token')});
 await assert.rejects(()=>e.transport.authenticate({email:'account@example.org',password:'sensitive'}),err=>
  err.message==='access_x_auth_unavailable'&&!err.message.includes('password'));
});
test('Auth transport is a stage-only server module and cannot open the live maintenance gate',()=>{
 const fs=require('node:fs'),path=require('node:path');const root=path.resolve(__dirname,'..');
 const source=fs.readFileSync(path.join(root,'access-x/server/supabase-auth-transport.cjs'),'utf8');
 const release=fs.readFileSync(path.join(root,'vercel.json'),'utf8');
 const loginUI=fs.readFileSync(path.join(root,'auth.js'),'utf8');
 assert.doesNotMatch(source,/process\.env|SUPABASE_SERVICE_ROLE|localStorage|sessionStorage/);
 assert.match(release,/maintenance\.html/);
 assert.doesNotMatch(loginUI,/sb_secret_|service_role|access-x\/server\/supabase-auth-transport/);
});
