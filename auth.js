(function(root){
 'use strict';
 const doc=root.document;
 const form=doc?.getElementById('auth-form');
 if(!form)return;
 const email=doc.getElementById('auth-email'),password=doc.getElementById('auth-password');
 const submit=doc.getElementById('auth-submit'),label=doc.getElementById('auth-submit-label');
 const status=doc.getElementById('auth-status'),toggle=doc.getElementById('auth-password-toggle'),caps=doc.getElementById('caps-lock');
 let busy=false;
 const routes=Object.freeze({manager:'/access-x/manager/',cashier:'/access-x/cashier/'});
 function message(text,tone='error'){
  status.textContent=text;status.hidden=!text;
  status.dataset.tone=tone;
 }
 function changeBusy(value){
  busy=value;submit.disabled=value;submit.setAttribute('aria-busy',String(value));
  email.readOnly=value;password.readOnly=value;
  label.textContent=value?'پشتڕاستکردنەوە…':'چوونەژوورەوە';
 }
 function validForm(){
  email.value=email.value.trim().toLowerCase();
  if(!email.value||!email.checkValidity()||email.value.length>254){message('ئیمەیڵەکەت بە دروستی بنووسە.');email.focus();return false;}
  if(!password.value){message('وشەی نهێنی بنووسە.');password.focus();return false;}
  if(password.value.length>1024){message('وشەی نهێنی نادروستە.');password.focus();return false;}
  return true;
 }
 function trustedDestination(payload){
  // Never take a destination, market ID or role from a query parameter.
  // These fixed routes are NOT published until the server-verified session API is operational.
  if(!payload||payload.state!=='authenticated'||!Object.hasOwn(routes,payload.role))return null;
  if(payload.verified!==true||payload.requires_password_change===true)return null;
  return routes[payload.role];
 }
 async function submitLogin(event){
  event.preventDefault();
  if(busy||!validForm())return;
  changeBusy(true);message('پشتڕاستکردنەوەی ناسنامە…','info');
  const credentials={email:email.value,password:password.value};
  try{
   // Server must independently verify Auth credentials, primary-owner/membership state and
   // completed first-login password change. No browser-side role or owner ID is authoritative.
   const response=await root.fetch('/api/access-x/login',{
    method:'POST',mode:'same-origin',credentials:'same-origin',cache:'no-store',redirect:'error',
    headers:{'Content-Type':'application/json','Accept':'application/json'},
    body:JSON.stringify(credentials)
   });
   if(response.status===429){message('هەوڵی چوونەژوورەوە زۆر بوو. کەمێک دواتر هەوڵ بدەرەوە.');return;}
   if(!response.ok){message('ئیمەیڵ یان وشەی نهێنی دروست نییە، یان هەژمارەکە مۆڵەتی چوونەژوورەوەی نییە.');return;}
   const contentType=response.headers?.get('content-type')||'';
   if(!/^\s*application\/json(?:\s*;|$)/i.test(contentType))throw Error('access_x_invalid_reply');
   const data=await response.json();
   if(data?.state==='password_change_required'){message('هەژمارەکەت هێشتا چالاک نەکراوە. پرۆسەی گۆڕینی وشەی نهێنی لە سێرڤەر تەواو دەبێت.','info');return;}
   const destination=trustedDestination(data);
   if(!destination)throw Error('access_x_unverified_role');
   // Client navigation happens only after an explicit server-verified role claim.
   root.location.assign(destination);
  }catch(_error){
   // A maintenance HTML response, missing API, connectivity failure or unexpected
   // response all FAIL CLOSED. Never attempt legacy browser-side authentication as a fallback.
   message('چوونەژوورەوە لە ئێستادا بەردەست نییە یان پەیوەندییەکە سەرکەوتوو نەبوو. دووبارە هەوڵ بدەرەوە.');
  }finally{
   password.value='';changeBusy(false);
  }
 }
 toggle.addEventListener('click',()=>{
  const show=password.type==='password';
  password.type=show?'text':'password';
  toggle.setAttribute('aria-pressed',String(show));
  toggle.setAttribute('aria-label',show?'شاردنەوەی وشەی نهێنی':'پیشاندانی وشەی نهێنی');
  toggle.title=show?'شاردنەوەی وشەی نهێنی':'پیشاندانی وشەی نهێنی';
 });
 password.addEventListener('keyup',event=>{caps.hidden=!event.getModifierState?.('CapsLock');});
 form.addEventListener('submit',submitLogin);
 root.KashierAccessXLogin=Object.freeze({trustedDestination});
})(window);
