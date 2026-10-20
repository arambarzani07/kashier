'use strict';
// Access X staged server-only cashier provisioning core.
// IMPORTANT: This is an adapter contract, NOT a deployed HTTP endpoint. Never import in a browser.
// No Supabase secret is stored here. Durable adapters must be installed only after DB backup/restore review.
const {createHash} = require('node:crypto');
const PERMISSIONS=Object.freeze(['can_credit','can_repay','can_refund','can_partial_refund','can_discount']);
class AccessXError extends Error {
 constructor(code){super(code);this.name='AccessXError';this.code=code;}
}
function fail(code){throw new AccessXError(code);}
function object(x){return x!==null&&typeof x==='object'&&!Array.isArray(x);}
function exactKeys(x,allowed){
 if(!object(x)||Object.keys(x).some(k=>!allowed.includes(k)))fail('invalid_payload');
}
function normalizeRequest(input){
 exactKeys(input,['request_id','name','login_email','permissions']);
 if(typeof input.request_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input.request_id))fail('invalid_request_id');
 if(typeof input.name!=='string')fail('invalid_name');
 const name=input.name.trim();
 if(!name||name.length>100||/[\u0000-\u001f\u007f]/u.test(name))fail('invalid_name');
 if(typeof input.login_email!=='string')fail('invalid_login_email');
 const email=input.login_email.trim().toLowerCase();
 if(email.length>254||!/^[-\w.+]+@[-\w]+(?:\.[-\w]+)+$/.test(email)||email.includes('..'))fail('invalid_login_email');
 const perms=input.permissions===undefined?{}:input.permissions;
 exactKeys(perms,PERMISSIONS);
 const permissions=Object.fromEntries(PERMISSIONS.map(k=>{
  if(Object.prototype.hasOwnProperty.call(perms,k)&&typeof perms[k]!=='boolean')fail('invalid_permissions');
  return [k,perms[k]===true];
 }));
 return Object.freeze({requestId:input.request_id.toLowerCase(),name,email,permissions:Object.freeze(permissions)});
}
function contentHash(normalized){
 return createHash('sha256').update(JSON.stringify({
  name:normalized.name,email:normalized.email,permissions:normalized.permissions
 })).digest('hex');
}
function ensureDeps(deps){
 for(const key of ['verifySession','requirePrimaryManager','requireFreshAuthentication','reserve','claim',
  'generateTemporaryPassword','createAuthUser','recordAuthIdentity','attachCashier','markReady','markForReconciliation']){
  if(typeof deps?.[key]!=='function')fail('server_adapter_missing');
 }
}
function ensureOwner(actor){
 if(!object(actor)||typeof actor.id!=='string'||
 !/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(actor.id)||
 actor.is_anonymous===true)fail('unauthorized');
}
async function provisionCashier(deps,{bearerToken,body}){
 ensureDeps(deps);
 const request=normalizeRequest(body);
 if(typeof bearerToken!=='string'||bearerToken.length<20)fail('unauthorized');
 const actor=await deps.verifySession(bearerToken);
 ensureOwner(actor);
 const ownerId=actor.id;
 // Both checks must read server-verified identity + database authority; JWT user_metadata is not authority.
 if(await deps.requirePrimaryManager(ownerId)!==true)fail('manager_required');
 if(await deps.requireFreshAuthentication(actor)!==true)fail('reauth_required');
 const payloadHash=contentHash(request);
 // Durable unique (ownerId,requestId), atomic payload-hash conflict check and row lock/CAS are required.
 const slot=await deps.reserve({ownerId,requestId:request.requestId,payloadHash});
 if(!object(slot)||!['new','completed','pending','reconciliation'].includes(slot.state))fail('reservation_invalid');
 if(slot.payloadHash!==payloadHash)fail('request_conflict');
 if(slot.state==='completed')return Object.freeze({status:'already_created',memberId:slot.memberId});
 if(slot.state==='pending')return Object.freeze({status:'pending'});
 if(slot.state==='reconciliation')return Object.freeze({status:'needs_reconciliation'});
 // A CAS claim may be lost to another concurrent invoker; NEVER duplicate auth.admin.createUser.
 if(await deps.claim({ownerId,requestId:request.requestId})!==true)
  return Object.freeze({status:'pending'});
 let memberId=null;
 try{
  const password=await deps.generateTemporaryPassword();
  if(typeof password!=='string'||password.length<20||password.length>128)fail('credential_generator_invalid');
  // Admin implementation MUST perform createUser server-side with no email invitation.
  // No role claims or owner authority may be derived from client fields.
  const created=await deps.createAuthUser({email:request.email,password});
  if(!object(created)||typeof created.id!=='string'||created.id===ownerId)fail('auth_creation_invalid');
  memberId=created.id;
  await deps.recordAuthIdentity({ownerId,requestId:request.requestId,memberId});
  // Durable membership transaction must enforce cashier-only, minimal permissions and audit actor.
  await deps.attachCashier({ownerId,memberId,requestId:request.requestId,
    name:request.name,permissions:request.permissions,role:'cashier'});
  await deps.markReady({ownerId,requestId:request.requestId,memberId});
  // One-time credential: never saved in logs, database reservations or replay responses.
  return Object.freeze({status:'created',memberId,temporaryPassword:password});
 }catch(_err){
  // Auth and Postgres aren't atomic; uncertain writes MUST NOT trigger blind delete/retry.
  // Persist a recovery ticket even if createUser succeeded but its response was lost.
  try{await deps.markForReconciliation({ownerId,requestId:request.requestId,memberId});}
  catch{fail('reconciliation_persistence_failed');}
  return Object.freeze({status:'needs_reconciliation'});
 }
}
module.exports={AccessXError,PERMISSIONS,normalizeRequest,contentHash,provisionCashier};
