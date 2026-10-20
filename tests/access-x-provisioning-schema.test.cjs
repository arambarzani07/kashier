'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const script=fs.readFileSync(path.join(root,'access-x/drafts/provisioning-reservation-schema.sql'),'utf8');
const core=fs.readFileSync(path.join(root,'access-x/provisioning-core.cjs'),'utf8');
test('provisioning reservation DDL stays out of executable production migrations',()=>{
 assert.equal(fs.existsSync(path.join(root,'supabase/migrations/20261020_access_x_provisioning_reservations.sql')),false);
 assert.match(script,/DRAFT ONLY.*NOT A LIVE MIGRATION/);
 assert.doesNotMatch(fs.readFileSync(path.join(root,'vercel.json'),'utf8'),/access-x/i);
});
test('private operational data table is RLS guarded and not client-granted',()=>{
 assert.match(script,/primary key \(owner_id, request_id\)/);
 assert.match(script,/payload_hash text not null check \(payload_hash/);
 assert.match(script,/member_id uuid unique references auth\.users\(id\)/);
 assert.match(script,/enable row level security/g);
 assert.match(script,/revoke all on public\.access_x_provisioning_requests,public\.access_x_provisioning_events[\s\S]*from public,anon,authenticated/);
 assert.match(script,/grant select,insert,update on public\.access_x_provisioning_requests to service_role/);
 assert.doesNotMatch(script,/grant\s+(?:all|select|insert|update)[\s\S]{0,75}\s+to authenticated\b/i);
});
test('every privileged RPC is invoker and service-role-only, not an anonymous security definer',()=>{
 const names=['reserve_request','claim_request','record_identity','mark_provisioned','mark_reconciliation'];
 for(const name of names){
  const identity='access_x_'+name;
  assert.match(script,new RegExp('create function public\\.'+identity+'\\('));
  assert.match(script,new RegExp('revoke all on function public\\.'+identity+'\\([\\s\\S]*?from public,anon,authenticated'));
  assert.match(script,new RegExp('grant execute on function public\\.'+identity+'\\([\\s\\S]*?to service_role'));
 }
 assert.equal((script.match(/language plpgsql security invoker set search_path=''/g)||[]).length,5);
 assert.doesNotMatch(script,/security definer/i);
});
test('one-way CAS and actor reconciliation, with no automatic claim recycle or active staff on issue',()=>{
 assert.match(script,/where owner_id=p_owner and request_id=p_request and payload_hash=p_hash and state='reserved'/);
 assert.match(script,/state='reconciliation'/);
 assert.match(script,/s\.role='cashier'[\s\S]{0,95}s\.enabled=false and s\.accepted_at is null/);
 assert.doesNotMatch(script,/state='active'/);
 assert.doesNotMatch(core,/markReady|status:'created'/);
 assert.match(core,/requiresFirstLogin:true/);
 assert.match(core,/status:'provisioned_pending_activation'/);
});
