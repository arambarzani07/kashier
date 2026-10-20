'use strict';
// Supabase Auth HTTP transport. SERVER ONLY, NOT DEPLOYED.
// Uses a strictly publishable/anon key; no service_role or database admin key.
// For real deployment use explicit server environment variables, not browser code.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function fail(){throw new Error('access_x_auth_unavailable');}
function publicKey(key){
 if(typeof key!=='string'||key.length<18||key.length>2000)fail();
 if(key.startsWith('sb_publishable_'))return key;
 if(key.startsWith('sb_secret_'))fail();
 // Legacy anon JWT only. Decode for *configuration hygiene*, NEVER for user authority.
 const segments=key.split('.');
 if(segments.length!==3||segments.some(x=>!/^[A-Za-z0-9_-]+$/.test(x)))fail();
 try{
  const claims=JSON.parse(Buffer.from(segments[1],'base64url').toString('utf8'));
  if(claims.role!=='anon')fail();
 }catch{fail();}
 return key;
}
function checkedOrigin(origin){
 if(typeof origin!=='string')fail();
 let url;
 try{url=new URL(origin);}catch{fail();}
 if(url.protocol!=='https:'||url.username||url.password||url.port||url.pathname!=='/'||url.search||url.hash||
    !/^[a-z0-9-]{10,60}\.supabase\.co$/i.test(url.hostname)||
    origin!==url.origin)fail();
 return url.origin;
}
function createSupabaseAuthTransport({projectUrl,anonKey,fetchImpl,timeoutMs=6000}={}){
 const origin=checkedOrigin(projectUrl),apiKey=publicKey(anonKey);
 const request=fetchImpl??globalThis.fetch;
 if(typeof request!=='function'||!Number.isInteger(timeoutMs)||timeoutMs<1000||timeoutMs>15000)fail();
 async function call(path,{method,accessToken,body}){
  const controller=new AbortController();
  const timeout=setTimeout(()=>controller.abort(),timeoutMs);
  try{
   const headers={'apikey':apiKey,'Accept':'application/json'};
   if(body!==undefined)headers['Content-Type']='application/json';
   if(accessToken!==undefined)headers.Authorization='Bearer '+accessToken;
   const response=await request(origin+path,{
    method,headers,body:body===undefined?undefined:JSON.stringify(body),
    redirect:'error',cache:'no-store',credentials:'omit',signal:controller.signal
   });
   if(!response||response.ok!==true||response.status!==200)fail();
   const kind=response.headers?.get?.('content-type')||'';
   if(!/^application\/json(?:\s*;|$)/i.test(kind))fail();
   const declared=Number(response.headers?.get?.('content-length')||0);
   if(declared>32768)fail();
   // Some providers omit Content-Length. Do not trust it to bound the response.
   const raw=await response.text();
   if(typeof raw!=='string'||Buffer.byteLength(raw,'utf8')>32768)fail();
   const value=JSON.parse(raw);
   if(!value||typeof value!=='object'||Array.isArray(value))fail();
   return value;
  }catch(_error){
   // Do not echo request body, auth tokens, email or upstream response errors.
   fail();
  }finally{clearTimeout(timeout);}
 }
 return Object.freeze({
  async authenticate({email,password}){
   if(typeof email!=='string'||typeof password!=='string'||!email||!password)fail();
   const result=await call('/auth/v1/token?grant_type=password',{
    method:'POST',body:{email,password}
   });
   const token=result.access_token;
   if(typeof token!=='string'||token.length<20||token.length>8192||
      !/^[A-Za-z0-9._~-]+$/.test(token)||result.token_type!=='bearer')fail();
   return {accessToken:token};
  },
  async verifyUser(accessToken){
   if(typeof accessToken!=='string'||accessToken.length<20||accessToken.length>8192||
      !/^[A-Za-z0-9._~-]+$/.test(accessToken))fail();
   const result=await call('/auth/v1/user',{method:'GET',accessToken});
   if(typeof result.id!=='string'||!uuid.test(result.id))fail();
   // Never return Supabase user_metadata/app_metadata for authorization decisions.
   return Object.freeze({id:result.id,is_anonymous:result.is_anonymous===true});
  }
 });
}
module.exports={createSupabaseAuthTransport};
