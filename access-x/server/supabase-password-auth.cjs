'use strict';
// Optional server-only Supabase GoTrue adapter. Never loaded in the browser.
// Does not provide role resolution, rate limiter, password-change activation or session storage.
function createSupabasePasswordAuth({supabaseUrl,publishableKey,fetchImpl=fetch}={}){
 if(typeof supabaseUrl!=='string'||!/^https:\/\/[a-z0-9.-]+(?::443)?\/?$/i.test(supabaseUrl)||
  typeof publishableKey!=='string'||!publishableKey||typeof fetchImpl!=='function')
  throw new Error('Supabase Auth server config is unavailable');
 const url=supabaseUrl.replace(/\/$/,'')+'/auth/v1';
 async function call(path,{method='GET',body,token}={}){
  const response=await fetchImpl(url+path,{
   method,
   redirect:'error',cache:'no-store',signal:AbortSignal.timeout(8000),
   headers:{apikey:publishableKey,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
   ...(body===undefined?{}:{body:JSON.stringify(body)})
  });
  if(!response||typeof response.ok!=='boolean')throw new Error('auth_transport_error');
  if(!response.ok){
   const error=new Error('auth_unavailable');
   // Only failed PASSWORD AUTH requests map to a generic invalid-credentials signal.
   if(response.status===400||response.status===401||response.status===422)error.code='invalid_credentials';
   throw error;
  }
  return response.json();
 }
 return Object.freeze({
  async passwordSignIn(email,password){return call('/token?grant_type=password',{method:'POST',body:{email,password}});},
  async verifyUser(accessToken){return call('/user',{token:accessToken});}
 });
}
module.exports={createSupabasePasswordAuth};
