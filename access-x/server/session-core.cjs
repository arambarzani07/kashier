'use strict';
// Kashêr Access X server-side OPAQUE session gate. Source-only; not an API route.
// Token is NEVER stored in plaintext. Backing store + role authorization MUST be durable.
const {randomBytes,createHash}=require('node:crypto');
const id=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const tokenPattern=/^[A-Za-z0-9_-]{43}$/;
function fail(){throw new Error('access_x_session_denied');}
function hashToken(token){if(typeof token!=='string'||!tokenPattern.test(token))fail();return createHash('sha256').update(token).digest('hex');}
function validScope({userId,scope}={}){
 return typeof userId==='string'&&id.test(userId)&&scope&&typeof scope==='object'&&
 id.test(scope.ownerId||'')&&id.test(scope.marketId||'')&&
 (scope.role==='cashier'||scope.role==='manager')&&
 (scope.role!=='manager'||scope.ownerId===userId)&&
 (scope.role!=='cashier'||scope.ownerId!==userId);
}
function parseSessionCookie(header){
 if(typeof header!=='string'||header.length>8192)return null;
 let found=null;
 for(const part of header.split(';')){
  const trimmed=part.trim(),marker='__Host-kashier_access_x=';
  if(!trimmed.startsWith(marker))continue;
  if(found!==null)return null; // Duplicate cookie names are ambiguous -> deny
  found=trimmed.slice(marker.length);
 }
 return typeof found==='string'&&tokenPattern.test(found)?found:null;
}
function createSessionManager({store,requireCurrentAccess,clock=()=>Date.now(),random=bytes=>randomBytes(bytes),ttlSeconds=600}={}){
 if(!store||typeof store.insert!=='function'||typeof store.get!=='function'||typeof store.revoke!=='function'||
 typeof requireCurrentAccess!=='function'||typeof clock!=='function'||typeof random!=='function'||
 !Number.isInteger(ttlSeconds)||ttlSeconds<60||ttlSeconds>900)fail();
 async function issueSession({userId,scope}={}){
  if(!validScope({userId,scope}))fail();
  const now=clock(),seed=random(32);
  if(!Number.isSafeInteger(now)||now<=0||!Buffer.isBuffer(seed)||seed.length!==32)fail();
  const token=seed.toString('base64url');
  if(!tokenPattern.test(token))fail();
  const h=hashToken(token),expiry=now+ttlSeconds*1000;
  if(await store.insert({
   tokenHash:h,userId,ownerId:scope.ownerId,marketId:scope.marketId,
   role:scope.role,expiresAt:expiry,createdAt:now
  })!==true)fail();
  return Object.freeze({token,ttlSeconds});
 }
 async function verifySession(cookieHeader){
  const token=parseSessionCookie(cookieHeader);
  if(!token)return null;
  const hash=hashToken(token);
  let row;
  try{row=await store.get(hash);}catch{return null;}
  const now=clock();
  if(!row||row.tokenHash!==hash||row.revokedAt!==null||
   !Number.isSafeInteger(now)||!Number.isSafeInteger(row.expiresAt)||row.expiresAt<=now||
   !validScope({userId:row.userId,scope:row})||row.expiresAt>now+900000)return null;
  const scope={role:row.role,ownerId:row.ownerId,marketId:row.marketId};
  try{
   // This must make a FRESH database authorization check on every request;
   // particularly important for immediate cashier revocation.
   if(await requireCurrentAccess({userId:row.userId,scope})!==true){
    await store.revoke(hash);return null;
   }
  }catch{return null;}
  return Object.freeze({userId:row.userId,role:row.role,ownerId:row.ownerId,marketId:row.marketId});
 }
 async function revokeSession(cookieHeader){
  const token=parseSessionCookie(cookieHeader);
  if(!token)return false;
  try{return await store.revoke(hashToken(token))===true;}catch{return false;}
 }
 return Object.freeze({issueSession,verifySession,revokeSession});
}
module.exports={createSessionManager,hashToken,parseSessionCookie};
