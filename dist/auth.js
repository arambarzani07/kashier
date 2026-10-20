(function(){'use strict';
const $=s=>document.querySelector(s),M=KashierAccess;let busy=false,legacy=false,alive=true;
const status=t=>$('#auth-status').textContent=t;
function controls(){for(const e of document.querySelectorAll('form input,form button,#legacy-login'))e.disabled=busy;}
function clearSecrets(){for(const id of ['password','current-password','new-password','confirm-password'])$('#'+id).value='';}
function route(p){if(!alive)return;M.profile(p);$('#auth-form').hidden=true;$('#setup-form').hidden=!p.needs_username;$('#change-form').hidden=p.needs_username||!p.must_change;$('#legacy-login').hidden=true;
 if(p.needs_username){$('#auth-title').textContent='ناوی بەکارهێنەر هەڵبژێرە';$('#auth-description').textContent='هەژمار و داتاکانت دەمێننەوە؛ ئەمە تەنها یەک جارە.';status('');}
 else if(p.must_change){$('#auth-title').textContent='وشەی نهێنیی خۆت دابنێ';$('#auth-description').textContent='پێش دەستپێکردن، وشەی کاتی بگۆڕە.';status('');}
 else {sessionStorage.removeItem('kashier.screen-locked.v1.'+KashierData.userId());location.replace(M.safeNext(new URLSearchParams(location.search).get('next'),p));}
}
async function run(work){if(busy)return;busy=true;controls();status('تکایە چاوەڕێ بکە…');try{await work();}catch(e){if(alive)status(e.message);}finally{clearSecrets();busy=false;if(alive)controls();}}
$('#show-password').addEventListener('click',()=>{const show=$('#password').type==='password';$('#password').type=show?'text':'password';$('#show-password').textContent=show?'شاردنەوە':'پیشاندان';$('#show-password').setAttribute('aria-pressed',String(show));});
$('#legacy-login').addEventListener('click',()=>{if(busy)return;legacy=!legacy;$('#username-label').textContent=legacy?'ئیمەیڵی هەژمارە کۆنەکەت':'ناوی بەکارهێنەر';$('#username').type=legacy?'email':'text';$('#username').maxLength=legacy?254:40;$('#username').value='';$('#legacy-login').textContent=legacy?'گەڕانەوە بۆ ناوی بەکارهێنەر':'خاوەنی هەژماری کۆنم';$('#auth-description').textContent=legacy?'بە ئیمەیڵ و وشەی پێشووت بچۆ ژوورەوە؛ پاشان ناوی بەکارهێنەر هەڵبژێرە.':'بە هەژماری تایبەتی خۆت بچۆ ژوورەوە.';status('');});
$('#auth-form').addEventListener('submit',e=>{e.preventDefault();if(!$('#auth-form').reportValidity())return;const name=$('#username').value.trim(),secret=$('#password').value;if(!legacy&&!M.username(name)){status('ناوی بەکارهێنەر بە پیتی ئینگلیزی و ژمارە بنووسە.');return;}run(async()=>route(await(legacy?KashierData.signInLegacy(name,secret):KashierData.signInUsername(name.toLowerCase(),secret))));});
$('#setup-form').addEventListener('submit',e=>{e.preventDefault();if(!$('#setup-form').reportValidity())return;run(async()=>{await KashierData.bindUsername($('#setup-username').value.trim().toLowerCase(),$('#setup-name').value.trim());route(await KashierData.getAccessProfile());});});
$('#change-form').addEventListener('submit',e=>{e.preventDefault();if(!$('#change-form').reportValidity())return;const current=$('#current-password').value,next=$('#new-password').value;if(next!==$('#confirm-password').value){status('دوو وشەی نوێ یەکسان نین.');return;}run(async()=>{await KashierData.changeAccessPassword(current,next);route(await KashierData.getAccessProfile());});});
window.addEventListener('pagehide',()=>{alive=false;clearSecrets();});
let locked=true;try{locked=sessionStorage.getItem('kashier.screen-locked.v1.'+KashierData.userId())==='true';}catch{}
if(KashierData.loggedIn()&&!locked)run(async()=>route(await KashierData.getAccessProfile()));
})();
