'use strict';
// Production-independent auth provider adapter; no service-role or API secrets included.
// Only a publishable/anon public key may be passed here. Explicit server-side role
// lookups, durable throttling, and session issuance must be separately implemented.
function validEndpoint(url){
 try{const u=new URL(url);return u.protocol==='https:'&&u.pathname==='/'&&
    u.hostname.endsWith('.supabase.co')&&!!u.hostname.split('.')[0]&& !u.username&&!u.password&&!u.search&&!u.hash;}
 catch{return false;}
}
function safePublicKey(k){
 if(typeof k!=='string'||!k.length||k.length>4096||k.startsWith('sb_secret_'))return false;
 if(k.startsWith('sb_publishable_'))return true;
 try{
  const [header,payload,signature]=k.split('.');if(!header||!payload||!signature)return false;
  return JSON.parse(Buffer.from(payload,'base64url').toString('utf8')).role==='anon';
 }catch{return false;}
}
function createSupabasePasswordAdapter({supabaseUrl,publishableKey,fetchImpl=globalThis.fetch}){
 if(!validEndpoint(supabaseUrl)||!safePublicKey(publishableKey)||typeof fetchImpl!=='function')
  throw Error('access_x_invalid_auth_provider_config');
 const base=new URL(supabaseUrl).origin;
 async function request(path,{method='GET',body,token}={}){
  const headers={'apikey':publishableKey,'Accept':'application/json'};
  if(method==='POST')headers['Content-Type']='application/json';
  if(token)headers.Authorization='Bearer '+token;
  const res=await fetchImpl(base+path,{method,headers,body:body&&JSON.stringify(body),redirect:'error',cache:'no-store',signal:AbortSignal.timeout(8000)});
  if(!res?.ok)return null;
  return res.json();
 }
 return Object.freeze({
  async authenticatePassword({email,password}){
   const result=await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password}});
   return typeof result?.access_token==='string'?{accessToken:result.access_token}:null;
  },
  async verifyUser({accessToken}){
   if(typeof accessToken!=='string'||accessToken.length<20)return null;
   const user=await request('/auth/v1/user',{token:accessToken});
   return typeof user?.id==='string'&&!user.is_anonymous?{id:user.id,is_anonymous:false}:null;
  }
 });
}
module.exports={createSupabasePasswordAdapter};