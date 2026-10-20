// No third-party dependencies, password storage or credential logging.
const base=Deno.env.get('SUPABASE_URL')!;
const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const publicKey=Deno.env.get('SUPABASE_ANON_KEY')!;
const origin='https://kashier-hazel.vercel.app';
const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
class AccessError extends Error {code:string;status:number;constructor(code:string,status=400){super(code);this.code=code;this.status=status}}
async function api(path:string,body:unknown,key=service,token?:string,method='POST'){
 const r=await fetch(base+path,{method,headers:{apikey:key,Authorization:'Bearer '+(token||key),'Content-Type':'application/json'},...(body!==undefined?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});
 const data=await r.json();
 if(!r.ok){const code=String(data.message||data.code||'access_failed');throw new AccessError(data.code==='23505'?'access_conflict':code.startsWith('access_')?code:'access_failed',r.status===429?429:400)}
 return data;
}
const uuid=(v:unknown)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
function sessionId(token:string){try{return JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))).session_id}catch{throw new AccessError('access_denied',401)}}
const password=(v:unknown)=>typeof v==='string'&&v.length>=12&&v.length<=128&&v.trim().length>=12;
async function command(action:string,actor:string|null,body:Record<string,unknown>={}){return api('/rest/v1/rpc/access_admin',{p_action:action,p_actor:actor,p_body:body})}
async function identified(token:string){
 if(!token)throw new AccessError('access_denied',401);
 const user=await api('/auth/v1/user',undefined,publicKey,token,'GET');
 if(!uuid(user.id)||!uuid(sessionId(token)))throw new AccessError('access_denied',401);
 return {user,sid:sessionId(token)};
}
export async function handle(req:Request){
 if(req.headers.has('origin')&&req.headers.get('origin')!==origin)return new Response(null,{status:403});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return new Response(null,{status:405,headers:cors});
 try{
  const raw=await req.text();if(raw.length>8192)throw new AccessError('access_invalid');
  const b=JSON.parse(raw);if(!b||typeof b!=='object'||Array.isArray(b))throw new AccessError('access_invalid');
  let result;
  if(b.action==='login'||b.action==='legacy'){
   if(typeof b.password!=='string'||b.password.length<1||b.password.length>128)throw new AccessError('access_credentials',401);
   let email=b.email;
   if(b.action==='login'){
    if(typeof b.username!=='string'||b.username.length>40)throw new AccessError('access_credentials',401);
    const network=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';
    const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(network)))).map(x=>x.toString(16).padStart(2,'0')).join('');
    const lookup=await command('login',null,{username:b.username,network:hash});
    if(lookup.limited)throw new AccessError('access_limited',429);email=lookup.email;
   }
   if(typeof email!=='string'||email.length>254)throw new AccessError('access_credentials',401);
   let session;try{session=await api('/auth/v1/token?grant_type=password',{email,password:b.password},publicKey)}catch{throw new AccessError('access_credentials',401)}
   let profile;try{profile=await command('profile',session.user.id,{_session:sessionId(session.access_token)})}catch{throw new AccessError('access_credentials',401)}
   if(b.action==='legacy'&&!profile.needs_username)throw new AccessError('access_use_username',401);
   result={session,profile};
  }else{
   const token=req.headers.get('Authorization')?.replace(/^Bearer /i,'')||'';
   const {user,sid}=await identified(token);
   const secured={...b,_session:sid};
   // Credentials only go to Supabase Auth, never RPC bodies or database rows.
   delete secured.password;delete secured.current;
   const profile=await command('profile',user.id,{_session:sid});
   if(b.action==='profile')result=profile;
   else if(b.action==='bind')result=await command('bind',user.id,secured);
   else if(b.action==='password'){
    if(!password(b.password)||typeof b.current!=='string'||b.current.length>128||b.password===b.current)throw new AccessError('access_password');
    let fresh;try{fresh=await api('/auth/v1/token?grant_type=password',{email:user.email,password:b.current},publicKey)}catch{throw new AccessError('access_credentials',401)}
    if(fresh.user?.id!==user.id)throw new AccessError('access_denied',401);
    await api('/auth/v1/user',{password:b.password,current_password:b.current},publicKey,fresh.access_token,'PUT');
    await command('password_done',user.id,{_session:sessionId(fresh.access_token)});
    result={session:fresh};
   }else{
    if(profile.role!=='owner'||profile.needs_username||profile.must_change)throw new AccessError('access_denied',403);
    if(b.action==='list')result=await command('list',user.id,secured);
    else if(b.action==='create'){
     if(!uuid(b.request_id)||!password(b.password))throw new AccessError('access_password');
     const reserved=await command('reserve',user.id,secured);
     if(!reserved.user_id){
      try{await api('/auth/v1/admin/users',{email:reserved.email,password:b.password,email_confirm:true})}
      catch(e){const retry=await command('reserve',user.id,secured);if(!retry.user_id)throw e}
     }
     result=await command('finish',user.id,secured);
    }else if(b.action==='update'||b.action==='revoke')result=await command(b.action,user.id,secured);
    else if(b.action==='reset'){
     if(!password(b.password))throw new AccessError('access_password');
     // Revoke business access before the Auth mutation, including unknown outcomes.
     const target=await command('reset_begin',user.id,secured);
     await api('/auth/v1/admin/users/'+target.user_id,{password:b.password},service,undefined,'PUT');
     result={ok:true};
    }else throw new AccessError('access_invalid');
   }
  }
  return Response.json(result,{headers:cors});
 }catch(e){
  const known=e instanceof AccessError;
  return Response.json({code:known?e.code:'access_failed'},{status:known?e.status:400,headers:cors});
 }
}
Deno.serve(handle);
