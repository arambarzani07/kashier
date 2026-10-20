'use strict';
// Server-only Access X login orchestration — not a deployed route.
// No database admin key, browser token storage, guessed manager role or mock access fallback.
const {randomBytes,createHash}=require('node:crypto');
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
class LoginError extends Error{
 constructor(code){super(code);this.name='AccessXLoginError';this.code=code;}
}
function requireUUID(s){return typeof s==='string'&&UUID.test(s);}
function cleanCredentials(input){
 if(!input||typeof input!=='object'||Array.isArray(input))throw new LoginError('invalid_request');
 if(Object.keys(input).length!==2||!Object.hasOwn(input,'email')||!Object.hasOwn(input,'password'))throw new LoginError('invalid_request');
 if(typeof input.email!=='string'||typeof input.password!=='string')throw new LoginError('invalid_request');
 const email=input.email.trim().toLowerCase();
 if(email.length>254||!/^[-\w.+]+@[-\w]+(?:\.[-\w]+)+$/.test(email)||email.includes('..')
 ||!input.password||input.password.length>1024)throw new LoginError('invalid_request');
 return {email,password:input.password};
}
function requireAdapter(adapter){
 for(const name of ['checkRateLimit','passwordSignIn','verifyUser','resolveAccess','commitSession'])
  if(typeof adapter?.[name]!=='function')throw new LoginError('unconfigured');
}
function assessAccess(user,access){
 // Strict server-derived DB authority: no untrusted user-editable JWT claims, unverified role, or arbitrary
 // client-selected market. Multiple market memberships require an explicit separate design.
 if(!access||typeof access!=='object'||Array.isArray(access))return 'denied';
 if(access.state==='password_change_required'){
  return access.role==='cashier'&&access.userId===user.id&&requireUUID(access.ownerId)&&
    access.ownerId!==user.id&&access.provisioned===true&&access.enabled===false&&
    access.credentialRotationPending===true?'password_change_required':'denied';
 }
 if(access.state!=='active'||access.verifiedByDatabase!==true)return 'denied';
 if(access.role==='manager'){
  return access.userId===user.id&&access.ownerId===user.id&&access.primaryOwner===true?
   {role:'manager',ownerId:access.ownerId}:'denied';
 }
 if(access.role==='cashier'){
  return access.userId===user.id&&requireUUID(access.ownerId)&&access.ownerId!==user.id&&
   access.enabled===true&&access.accepted===true&&access.credentialRotationComplete===true&&
   access.membershipsCount===1?{role:'cashier',ownerId:access.ownerId}:'denied';
 }
 return 'denied';
}
async function authenticateAccessX(adapter,body,context){
 requireAdapter(adapter);
 const credentials=cleanCredentials(body);
 if(!context||typeof context.ip!=='string'||!context.ip||
   typeof context.userAgent!=='string')throw new LoginError('invalid_context');
 let allowed;
 try{allowed=await adapter.checkRateLimit({ip:context.ip,email:credentials.email});}
 catch{throw new LoginError('unavailable');}
 if(allowed!==true)throw new LoginError(allowed===false?'rate_limited':'unavailable');
 let initial;
 try{initial=await adapter.passwordSignIn(credentials.email,credentials.password);}
 catch(error){throw new LoginError(error?.code==='invalid_credentials'?'invalid_credentials':'unavailable');}
 // Validate access token using Supabase Auth's trusted user endpoint, never decode JWT
 // without signature verification or accept an unauthenticated metadata role.
 if(!initial||!requireUUID(initial.user?.id)||typeof initial.access_token!=='string'||
    initial.access_token.length<20)throw new LoginError('invalid_credentials');
 let user;
 try{user=await adapter.verifyUser(initial.access_token);}
 catch{throw new LoginError('unavailable');}
 if(!requireUUID(user?.id)||user.id!==initial.user.id||user.is_anonymous===true)
  throw new LoginError('invalid_credentials');
 let access;
 try{access=await adapter.resolveAccess(user.id);}
 catch{throw new LoginError('unavailable');}
 const assessment=assessAccess(user,access);
 if(assessment==='password_change_required')return Object.freeze({state:'password_change_required'});
 if(assessment==='denied')throw new LoginError('invalid_credentials');
 // Opaque random session handle: browser receives no Supabase JWT/refresh token.
 // Authenticated business routes MUST re-check current membership/manager status in DB
 // and ensure server session is not revoked or expired for EVERY protected operation.
 const secret=randomBytes(32).toString('base64url');
 const tokenHash=createHash('sha256').update(secret).digest('hex');
 const subject=Object.freeze({
  tokenHash, userId:user.id,ownerId:assessment.ownerId,role:assessment.role,
  expiresInSeconds:600,ip:context.ip
 });
 try{if(await adapter.commitSession(subject)!==true)throw Error('session_not_saved');}
 catch{throw new LoginError('unavailable');}
 return Object.freeze({state:'authenticated',verified:true,role:assessment.role,sessionSecret:secret});
}
module.exports={LoginError,cleanCredentials,assessAccess,authenticateAccessX};
