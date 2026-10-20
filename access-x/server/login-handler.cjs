'use strict';
// Staged HTTP handler factory. Not mapped in Vercel or a Supabase Edge Function.
// All server dependencies must be provisioned explicitly; missing dependencies deny login.
const {authenticateAccessX,LoginError}=require('./login-service.cjs');
const MAX_BODY=2048;
function json(res,status,body,cookie){
 res.statusCode=status;
 res.setHeader('Content-Type','application/json; charset=utf-8');
 res.setHeader('Cache-Control','no-store, private');
 res.setHeader('Pragma','no-cache');
 res.setHeader('X-Content-Type-Options','nosniff');
 if(cookie)res.setHeader('Set-Cookie',cookie);
 res.end(JSON.stringify(body));
}
async function parseBody(req){
 if(req.body!==undefined){
  if(typeof req.body==='string'){
   if(Buffer.byteLength(req.body,'utf8')>MAX_BODY)throw new LoginError('too_large');
   try{return JSON.parse(req.body);}catch{throw new LoginError('invalid_request');}
  }
  if(!req.body||typeof req.body!=='object'||Array.isArray(req.body))throw new LoginError('invalid_request');
  if(Buffer.byteLength(JSON.stringify(req.body),'utf8')>MAX_BODY)throw new LoginError('too_large');
  return req.body;
 }
 let total=0;
 const buffers=[];
 if(!req[Symbol.asyncIterator])throw new LoginError('invalid_request');
 try{
  for await(const chunk of req){
   if(!Buffer.isBuffer(chunk)&&typeof chunk!=='string')throw new LoginError('invalid_request');
   const b=Buffer.isBuffer(chunk)?chunk:Buffer.from(chunk);
   total+=b.length;
   if(total>MAX_BODY)throw new LoginError('too_large');
   buffers.push(b);
  }
  return JSON.parse(Buffer.concat(buffers).toString('utf8'));
 }catch(e){
  if(e instanceof LoginError)throw e;
  throw new LoginError('invalid_request');
 }
}
function createLoginHandler(adapter,{allowedOrigin}={}){
 if(typeof allowedOrigin!=='string'||!/^https:\/\/[^/?#]+$/.test(allowedOrigin))
  throw new Error('Access X requires an explicit HTTPS origin');
 const origin=new URL(allowedOrigin).origin;
 return async function loginHandler(req,res){
  const headers=req?.headers||{};
  if(req?.method!=='POST'){
   res.setHeader('Allow','POST');
   return json(res,405,{state:'unavailable'});
  }
  // Strict same-origin check: never derive allowed origin from the request Host or Origin.
  if(headers.origin!==origin||headers['sec-fetch-site']&&headers['sec-fetch-site']!=='same-origin')
   return json(res,403,{state:'denied'});
  if(!/^application\/json(?:\s*;|$)/i.test(headers['content-type']||''))
   return json(res,415,{state:'invalid_request'});
  const declared=Number(headers['content-length']);
  if(Number.isFinite(declared)&&declared>MAX_BODY)return json(res,413,{state:'invalid_request'});
  let body;
  try{body=await parseBody(req);}
  catch(e){return json(res,e.code==='too_large'?413:400,{state:'invalid_request'});}
  try{
   const result=await authenticateAccessX(adapter,body,{
    // A future runtime must derive IP from a trusted platform-provided property.
    // Never treat arbitrary X-Forwarded-For as proof of client IP.
    ip:typeof req.trustedClientIp==='string'?req.trustedClientIp:'',
    userAgent:typeof headers['user-agent']==='string'?headers['user-agent']:''
   });
   if(result.state==='password_change_required')
    return json(res,200,{state:'password_change_required'});
   const cookie='__Host-kashier_ax='+result.sessionSecret+
    '; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=600';
   return json(res,200,{state:'authenticated',verified:true,role:result.role},cookie);
  }catch(e){
   const code=e instanceof LoginError?e.code:'unavailable';
   if(code==='rate_limited')return json(res,429,{state:'denied'});
   if(code==='invalid_request')return json(res,400,{state:'invalid_request'});
   if(code==='invalid_credentials')return json(res,401,{state:'denied'});
   // Missing secrets, missing server session store, DB/network errors all fail closed.
   return json(res,503,{state:'unavailable'});
  }
 };
}
module.exports={createLoginHandler,parseBody};
