'use strict';
// STAGED, SERVER-ONLY: a fail-closed HTTP contract, not a registered production endpoint.
// No frontend fallback, no client-selected manager/cashier role, no persistent session store here.
const {createHash}=require('node:crypto');
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COOKIE='__Host-ax_sid';
const TTL_SECONDS=8*60*60;
const DEFAULT_HEADERS=Object.freeze({
 'Cache-Control':'no-store, private, max-age=0',
 'Content-Type':'application/json; charset=utf-8',
 'X-Content-Type-Options':'nosniff',
 'Referrer-Policy':'no-referrer',
 'X-Frame-Options':'DENY',
 'Pragma':'no-cache'
});
function response(status,payload,additional){return {status,headers:{...DEFAULT_HEADERS,...additional},body:JSON.stringify(payload)};}
function fail(status='invalid_credentials'){return response(401,{state:status});}
function isObject(value){return value!==null&&typeof value==='object'&&!Array.isArray(value);}
function parseCredentials(raw){
 if(typeof raw!=='string'||Buffer.byteLength(raw,'utf8')>4096) return null;
 let o;try{o=JSON.parse(raw);}catch{return null;}
 if(!isObject(o)||Object.keys(o).length!==2||Object.keys(o).some(k=>k!=='email'&&k!=='password'))return null;
 if(typeof o.email!=='string'||typeof o.password!=='string')return null;
 const email=o.email.trim().toLowerCase();
 if(email.length<3||email.length>254||!/^[-\w.+]+@[-\w]+(?:\.[-\w]+)+$/.test(email)||email.includes('..'))return null;
 if(!o.password||o.password.length>1024)return null;
 return {email,password:o.password};
}
function requiredDependencies(d){
 if(!isObject(d)||d.releaseGate!==true||typeof d.expectedOrigin!=='string')return false;
 try{const u=new URL(d.expectedOrigin);if(u.protocol!=='https:'||u.origin!==d.expectedOrigin)return false;}
 catch{return false;}
 return ['rateLimit','authenticatePassword','verifyUser','resolveAuthority','createSession'].every(k=>typeof d[k]==='function');
}
function authorityOf(user,proof){
 if(!isObject(user)||!UUID.test(user.id)||user.is_anonymous===true||!isObject(proof))return null;
 // A primary manager is NOT 'any authenticated user'; a server-owned market registry
 // must confirm this exact user is the primary account owner.
 if(proof.source==='primary_owner_database'&&proof.role==='manager'&&proof.active===true&&
    proof.ownerId===user.id&&UUID.test(proof.ownerId)&&proof.marketApproved===true)
  return {role:'manager',ownerId:proof.ownerId};
 // A cashier must have one server-selected, accepted and enabled membership; only
 // database-backed proof is valid. Unaccepted provisioned staff remain inactive.
 if(proof.source==='cashier_membership_database'&&proof.role==='cashier'&&
    proof.memberId===user.id&&UUID.test(proof.ownerId)&&proof.ownerId!==user.id&&
    proof.enabled===true&&proof.accepted===true&&proof.marketApproved===true&&
    proof.uniqueMarket===true&&proof.passwordRotated===true)
  return {role:'cashier',ownerId:proof.ownerId};
 return null;
}
async function handleLogin(req,deps){
 // Even valid users cannot sign in until the real recovery and authorization gates
 // are approved in the durable server environment. This code ships with NO active endpoint.
 if(!requiredDependencies(deps))return response(503,{state:'unavailable'});
 if(req?.method!=='POST')return response(405,{state:'method_not_allowed'},{Allow:'POST'});
 const h=req.headers||{};
 if(h.origin!==deps.expectedOrigin||h['sec-fetch-site']==='cross-site')return response(403,{state:'forbidden'});
 if(!/^application\/json(?:\s*;|\s*$)/i.test(h['content-type']||''))return response(415,{state:'unsupported_media_type'});
 const body=req.body;
 if(typeof body!=='string'||Buffer.byteLength(body,'utf8')>4096)return response(413,{state:'request_too_large'});
 const c=parseCredentials(body);if(!c)return response(400,{state:'invalid_request'});
 const key=createHash('sha256').update(c.email).digest('hex');
 try{
  // Rate limit MUST use durable, multi-instance shared storage, not local memory.
  const limit=await deps.rateLimit({loginKey:key,clientIp:req.clientIp||null});
  if(limit!==true)return response(429,{state:'rate_limited'},{'Retry-After':'60'});
  const auth=await deps.authenticatePassword({email:c.email,password:c.password});
  if(!isObject(auth)||typeof auth.accessToken!=='string'||auth.accessToken.length<20)return fail();
  // Always recheck with Auth provider: never authorize from a decoded/stale JWT payload.
  const user=await deps.verifyUser({accessToken:auth.accessToken});
  if(!isObject(user)||!UUID.test(user.id)||user.is_anonymous===true)return fail();
  // No JWT user_metadata, unverified role field or client owner_id is trusted.
  const proof=await deps.resolveAuthority({userId:user.id});
  if(isObject(proof)&&proof.source==='cashier_membership_database'&&
    proof.memberId===user.id&&proof.enabled===false&&proof.passwordRotated===false){
    // No privileged cookie until credential rotation/activation server is implemented.
    return response(200,{state:'password_change_required'});
  }
  const role=authorityOf(user,proof);
  if(!role)return fail();
  const issued=await deps.createSession({userId:user.id,ownerId:role.ownerId,role:role.role,
    authAccessToken:auth.accessToken,ttlSeconds:TTL_SECONDS});
  // Opaque, unpredictable server-persisted session handles ONLY. Never expose access token.
  if(!isObject(issued)||typeof issued.opaqueId!=='string'||
     !/^[A-Za-z0-9_-]{43,128}$/.test(issued.opaqueId))return response(503,{state:'unavailable'});
  return response(200,{state:'authenticated',verified:true,role:role.role},
    {'Set-Cookie':`${COOKIE}=${issued.opaqueId}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${TTL_SECONDS}`});
 }catch(_err){
  // Never log passwords, JWTs, Auth provider error payloads, or customer details.
  return response(503,{state:'unavailable'});
 }
}
module.exports={handleLogin,authorityOf,parseCredentials,requiredDependencies,TTL_SECONDS};