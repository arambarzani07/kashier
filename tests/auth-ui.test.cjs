'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {setImmediate:soon}=require('node:timers');
const tick=()=>new Promise(r=>soon(r));
const source=fs.readFileSync(require.resolve('../auth.js'),'utf8');
const html=fs.readFileSync(require.resolve('../auth.html'),'utf8');
const css=fs.readFileSync(require.resolve('../auth-access-x.css'),'utf8');
function setup({fetchImpl=async()=>({ok:false,status:503,headers:{get:()=> 'application/json'},json:async()=>({})}),validEmail=true}={}){
 const nodes=new Map(),calls=[],redirects=[];
 class Node{
  constructor(id){this.id=id;this.value='';this.textContent='';this.hidden=false;this.disabled=false;this.readOnly=false;this.type='password';this.dataset={};this.events={};this.attributes={};}
  addEventListener(k,fn){this.events[k]=fn;}
  setAttribute(k,v){this.attributes[k]=v;}
  focus(){this.focused=true;}
  checkValidity(){return validEmail;}
 }
 const ids=['auth-form','auth-email','auth-password','auth-submit','auth-submit-label','auth-status','auth-password-toggle','caps-lock'];
 for(const id of ids)nodes.set(id,new Node(id));
 const doc={getElementById:id=>nodes.get(id)||null};
 const win={document:doc,location:{assign:where=>redirects.push(where)},fetch:async(...args)=>{calls.push(args);return fetchImpl(...args);}};
 const context={window:win,document:doc,Object,JSON,console};
 vm.runInNewContext(source,context);
 return {
  calls,redirects,get:id=>nodes.get(id),trusted:win.KashierAccessXLogin.trustedDestination,
  send(){nodes.get('auth-form').events.submit({preventDefault(){}});},
  fill(email='cashier@example.org',password='a genuine password'){nodes.get('auth-email').value=email;nodes.get('auth-password').value=password;}
 };
}
function reply(payload,{status=200,contentType='application/json'}={}){
 return {status,ok:status>=200&&status<300,headers:{get:()=>contentType},json:async()=>payload};
}
test('new staged login is Sorani RTL, responsive and has no self-signup or invitation',()=>{
 assert.match(html,/<html lang="ckb" dir="rtl">/);
 assert.match(html,/auth-access-x\.css/);
 assert.match(html,/id="auth-form"/);
 assert.match(html,/id="auth-password"/);
 assert.match(html,/autocomplete="current-password"/);
 assert.match(html,/<script src="preferences\.js" defer>/);
 assert.doesNotMatch(html,/src="(?:config|data)\.js"/);
 assert.doesNotMatch(html,/id="signup"|type="password"[^>]*autocomplete="new-password"|id="confirm-password"/);
 assert.doesNotMatch(source,/KashierData|signUp\(|\/auth\/v1\/signup|localStorage|sessionStorage/);
 assert.match(css,/@media\(max-width:560px\)/);
 assert.match(css, /prefers-reduced-motion/);
});
test('valid login sends credentials only to fixed same-origin server endpoint',async()=>{
 const x=setup({fetchImpl:async()=>reply({state:'authenticated',verified:true,role:'cashier'})});
 x.fill(' Cashier@Example.ORG ');
 x.send();await tick();
 assert.equal(x.calls.length,1);
 assert.equal(x.calls[0][0],'/api/access-x/login');
 const opt=x.calls[0][1];
 assert.equal(opt.method,'POST');assert.equal(opt.credentials,'same-origin');
 assert.equal(opt.cache,'no-store');assert.equal(opt.redirect,'error');
 assert.equal(opt.mode,'same-origin');
 const data=JSON.parse(opt.body);
 assert.equal(data.email,'cashier@example.org');
 assert.equal(data.password,'a genuine password');
 assert.equal(Object.keys(data).sort().join(','),'email,password');
 assert.deepEqual(x.redirects,['/access-x/cashier/']);
 assert.equal(x.get('auth-password').value,'');
 assert.equal(x.get('auth-submit').disabled,false);
});
test('manager landing requires server authenticated and verified response',async()=>{
 const x=setup({fetchImpl:async()=>reply({state:'authenticated',role:'manager',verified:true})});
 x.fill();x.send();await tick();
 assert.deepEqual(x.redirects,['/access-x/manager/']);
});
test('untrusted roles, unverified claims and redirects fail closed',async()=>{
 for(const data of [
  {state:'authenticated',verified:true,role:'owner'},
  {state:'authenticated',verified:true,role:'admin'},
  {state:'authenticated',verified:false,role:'manager'},
  {state:'authenticated',role:'manager'},
  {state:'authenticated',verified:true,role:'cashier',requires_password_change:true},
  {state:'anything',verified:true,role:'cashier'}
 ]){
  const x=setup({fetchImpl:async()=>reply(data)});
  x.fill();x.send();await tick();
  assert.equal(x.redirects.length,0,JSON.stringify(data));
  assert.equal(x.get('auth-status').hidden,false);
 }
 const x=setup();assert.equal(x.trusted({state:'authenticated',verified:true,role:'admin'}),null);
});
test('first-login password rotation response never opens cashier workspace',async()=>{
 const x=setup({fetchImpl:async()=>reply({state:'password_change_required',role:'cashier'})});
 x.fill();x.send();await tick();
 assert.deepEqual(x.redirects,[]);
 assert.match(x.get('auth-status').textContent,/گۆڕینی وشەی نهێنی/);
});
test('maintenance HTML, request errors and 429 never redirect or use legacy auth',async()=>{
 for(const f of [
  async()=>reply({}, {contentType:'text/html'}),
  async()=>{throw Error('network failure');},
  async()=>reply({}, {status:429}),
  async()=>reply({}, {status:401})
 ]){
  const x=setup({fetchImpl:f});x.fill();x.send();await tick();
  assert.deepEqual(x.redirects,[]);
  assert.equal(x.get('auth-status').hidden,false);
  assert.equal(x.get('auth-password').value,'');
 }
});
test('validation blocks blank or invalid email and empty password without network request',async()=>{
 for(const options of [{email:'',password:'a'},{email:'bad',password:'a',validEmail:false},{email:'a@b.com',password:''}]){
  const x=setup({validEmail:options.validEmail!==false});x.fill(options.email,options.password);x.send();await tick();
  assert.equal(x.calls.length,0);
  assert.equal(x.get('auth-status').hidden,false);
 }
});
test('concurrent submits cannot double-send credentials',async()=>{
 let resolve;
 const x=setup({fetchImpl:()=>new Promise(r=>resolve=r)});
 x.fill();x.send();x.send();assert.equal(x.calls.length,1);
 assert.equal(x.get('auth-submit').disabled,true);
 resolve(reply({state:'authenticated',verified:true,role:'cashier'}));await tick();
 assert.equal(x.calls.length,1);assert.equal(x.get('auth-submit').disabled,false);
});
test('password visibility works without sending a request',()=>{
 const x=setup(),button=x.get('auth-password-toggle');
 button.events.click();assert.equal(x.get('auth-password').type,'text');assert.equal(button.attributes['aria-pressed'],'true');
 button.events.click();assert.equal(x.get('auth-password').type,'password');assert.equal(button.attributes['aria-pressed'],'false');
 assert.equal(x.calls.length,0);
});
test('role and redirect cannot be chosen through query arguments',async()=>{
 const x=setup({fetchImpl:async()=>reply({state:'authenticated',verified:true,role:'cashier',next:'https://evil.example'})});
 x.fill();x.send();await tick();
 assert.deepEqual(x.redirects,['/access-x/cashier/']);
});
