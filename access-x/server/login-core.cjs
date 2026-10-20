'use strict';
// STAGED, SERVER-ONLY Access X login. NO live endpoint/secret is installed.
// A verified Supabase Auth user is NOT automatically a primary market owner.
// All actual owner scope and staff state is resolved through privileged, reviewed
// server adapters after auth.getUser(access_token), never user_metadata or browser claims.
const { randomBytes }=require('node:crypto');
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const required=['authenticate','verifyUser','ownedScopes','memberships','credentialPolicy','issueSession'];
const isObj=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
function error(code){const e=new Error(code);e.code=code;throw e;}
function emailAndPassword(data){
 if(!isObj(data)||Object.keys(data).sort().join(',')!=='email,password')error('invalid_credentials');
 if(typeof data.email!=='string'||typeof data.password!=='string')error('invalid_credentials');
 const email=data.email.trim().toLowerCase();
 if(email.length>254||!/^[-\w.+]+@[-\w]+(?:\.[-\w]+)+$/.test(email)||email.includes('..'))error('invalid_credentials');
 if(!data.password||data.password.length>1024)error('invalid_credentials');
 return {email,password:data.password};
}
function requireAdapters(deps){
 if(!isObj(deps)||required.some(x=>typeof deps[x]!=='function'))error('server_adapter_missing');
}
async function resolveRole(deps,userId){
 if(typeof userId!=='string'||!UUID.test(userId))error('authorization_denied');
 const [owners,members]=await Promise.all([deps.ownedScopes(userId),deps.memberships(userId)]);
 if(!Array.isArray(owners)||!Array.isArray(members))error('authorization_denied');
 // No guessed owner role: requires exactly one positive *server-DB* owner registry row.
 // If an identity owns one market and is a cashier elsewhere, require future
 // explicit scoped workspace selection, not implicit access to the wrong store.
 if(owners.length+members.length!==1)error('authorization_denied');
 if(owners.length===1){
  const record=owners[0];
  if(!isObj(record)||record.ownerId!==userId||record.isPrimary!==true||record.enabled!==true||!UUID.test(record.marketId||''))error('authorization_denied');
  return Object.freeze({role:'manager',ownerId:userId,marketId:record.marketId});
 }
 const member=members[0];
 if(!isObj(member)||member.memberId!==userId||!UUID.test(member.ownerId||'')||
  !UUID.test(member.marketId||'')||member.ownerId===userId||member.role!=='cashier')error('authorization_denied');
 // Transitional delegated manager role is explicitly disallowed.
 if(member.enabled!==true||member.acceptedAt===null||typeof member.acceptedAt!=='string'){
  if(member.role==='cashier'&&member.enabled===false&&member.acceptedAt===null &&
     await deps.activationRequired?.({userId,ownerId:member.ownerId,marketId:member.marketId})===true){
   return Object.freeze({state:'password_change_required'});
  }
  error('authorization_denied');
 }
 return Object.freeze({role:'cashier',ownerId:member.ownerId,marketId:member.marketId});
}
async function login(deps,body){
 requireAdapters(deps);
 const {email,password}=emailAndPassword(body);
 const auth=await deps.authenticate({email,password});
 if(!isObj(auth)||typeof auth.accessToken!=='string'||auth.accessToken.length<20)error('invalid_credentials');
 // Auth response metadata and decoded JWT are NEVER the source of identity.
 const user=await deps.verifyUser(auth.accessToken);
 if(!isObj(user)||!UUID.test(user.id||'')||user.is_anonymous===true)error('invalid_credentials');
 const scope=await resolveRole(deps,user.id);
 if(scope.state==='password_change_required')return Object.freeze({state:'password_change_required'});
 const policy=await deps.credentialPolicy({userId:user.id,scope,accessToken:auth.accessToken});
 if(!isObj(policy)||policy.passwordRotated!==true||policy.allowed!==true)error('authorization_denied');
 if(scope.role==='manager'&&policy.aal!=='aal2')error('step_up_required');
 // Session identity must be opaque, persisted, linked to exact scope and rechecked
 // in every protected backend RPC; do not trust this cookie to bypass current DB RLS.
 const session=await deps.issueSession({userId:user.id,scope,accessToken:auth.accessToken});
 if(!isObj(session)||typeof session.token!=='string'||!/^[-_A-Za-z0-9]{43,256}$/.test(session.token)||
 !Number.isInteger(session.ttlSeconds)||session.ttlSeconds<1||session.ttlSeconds>900)error('invalid_session');
 return Object.freeze({state:'authenticated',role:scope.role,verified:true,sessionToken:session.token,ttlSeconds:session.ttlSeconds});
}
function jsonResponse(res,status,data,{cookie}={}){
 res.statusCode=status;
 res.setHeader('Content-Type','application/json; charset=utf-8');
 res.setHeader('Cache-Control','no-store, max-age=0');
 res.setHeader('Pragma','no-cache');
 res.setHeader('X-Content-Type-Options','nosniff');
 if(cookie)res.setHeader('Set-Cookie',cookie);
 res.end(JSON.stringify(data));
}
function createStagedHandler({enabled=false,origin,adapters}={}){
 // Default fail-closed. No Vercel route is installed by this file.
 if(enabled!==true)return async(_req,res)=>jsonResponse(res,503,{state:'unavailable'});
 if(typeof origin!=='string'||!/^https:\/\/[^/?#]+$/.test(origin))error('invalid_server_origin');
 requireAdapters(adapters);
 if(typeof adapters.rateLimit!=='function')error('rate_limit_adapter_missing');
 return async(req,res)=>{
  if(req.method!=='POST')return jsonResponse(res,405,{state:'unavailable'});
  if(req.headers?.origin!==origin)return jsonResponse(res,403,{state:'unavailable'});
  const ctype=req.headers?.['content-type']||'';
  if(!/^application\/json(?:\s*;|$)/i.test(ctype))return jsonResponse(res,415,{state:'unavailable'});
  const body=req.body;
  if(!isObj(body)||Buffer.byteLength(JSON.stringify(body),'utf8')>4096)
   return jsonResponse(res,400,{state:'unavailable'});
  try{
   // This adapter MUST rate-limit in shared durable storage using trustworthy
   // ingress metadata (not raw client X-Forwarded-For or username alone).
   if(await adapters.rateLimit({request:req})!==true)
    return jsonResponse(res,429,{state:'unavailable'});
   const result=await login(adapters,body);
   if(result.state==='password_change_required')
    return jsonResponse(res,200,{state:'password_change_required'});
   const cookie='__Host-kashier_access_x='+result.sessionToken+
    '; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age='+result.ttlSeconds;
   return jsonResponse(res,200,{state:'authenticated',role:result.role,verified:true},{cookie});
  }catch(_error){
   // Generic denial. Never disclose existence of email, membership, or passwords.
   return jsonResponse(res,401,{state:'unavailable'});
  }
 };
}
module.exports={emailAndPassword,resolveRole,login,createStagedHandler};
