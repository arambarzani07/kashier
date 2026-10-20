'use strict';
// Isolated schema equivalence verifier. Never accesses live Supabase or customer data.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const differences=new Set([
 'private.get_cashier_refund',
 'private.get_cashier_refund_sale',
 'private.get_cashier_refund_workspace',
 'private.post_cashier_refund',
 'private.post_sale_reversal_for_owner',
 'public.get_cash_statement',
 'public.get_supplier_payables_report'
]);
function tokenize(s){
 if(typeof s!=='string')throw Error('Source must be text');
 const tokens=[];let i=0;
 while(i<s.length){
  const c=s[i],d=s[i+1];
  if(/\s/.test(c)){i++;continue;}
  if(c==='-'&&d==='-'){const j=s.indexOf('\n',i+2);i=j<0?s.length:j+1;continue;}
  if(c==='/'&&d==='*'){const j=s.indexOf('*/',i+2);if(j<0)throw Error('Unclosed comment');i=j+2;continue;}
  if(c==="'"||c==='"'){
   let j=i+1,closed=false;
   while(j<s.length){if(s[j]===c){if(s[j+1]===c){j+=2;continue;}j++;closed=true;break;}j++;}
   if(!closed)throw Error('Unclosed literal');
   tokens.push(s.slice(i,j));i=j;continue;
  }
  if(c==='$'){const match=s.slice(i).match(/^\$[a-zA-Z_0-9]*\$/);
   if(match){tokens.push(match[0]);i+=match[0].length;continue;}
  }
  const match=s.slice(i).match(/^(?:[a-zA-Z_][a-zA-Z_0-9]*|[0-9]+(?:\.[0-9]+)?|::|->>|->|>=|<=|<>|!=|\|\||:=|[^\s])/);
  if(!match)throw Error('Invalid SQL token');tokens.push(match[0]);i+=match[0].length;
 }
 return tokens;
}
function canonical(name,tokens){
 if(name!=='public.get_cash_statement')return tokens;
 const result=[];
 for(let i=0;i<tokens.length;i++){
  // These two aliases alone are equivalent with or without optional SQL AS.
  if(tokens[i].toLowerCase()==='as'&&
    (tokens[i+1]==='purchase_id'||tokens[i+1]==='linked_sale_id')&&
    tokens[i-1]===')')continue;
  result.push(tokens[i]);
 }
 return result;
}
function uniqueLines(report,marker){
 const lines=report.split(/\r?\n/).filter(line=>line.startsWith(marker));
 if(new Set(lines).size!==lines.length)throw Error('Duplicate '+marker+' output');
 return lines;
}
function verifyReport(report,definitions,rights,functions){
 const expectedNames=Object.keys(functions).sort();
 assert.deepEqual(expectedNames,[...differences].sort(),'exactly seven reviewed routines required');
 const expectedRights=rights.trim().split(/\r?\n/).sort();
 const observedRights=uniqueLines(report,'AX_SEM|').sort();
 assert.equal(expectedRights.length,221);assert.deepEqual(observedRights,expectedRights,'effective grants or policy targets changed');
 const expectedDefs=definitions.trim().split(/\r?\n/).sort();
 const observedDefs=uniqueLines(report,'AX_META|').map(line=>{
  const parts=line.split('|');assert.equal(parts.length,5,'malformed object metadata');
  const fn=parts[2].split('(')[0];
  return parts[1]==='routine'&&differences.has(fn)?null:
   'AX_DEF|'+parts[1]+'|'+parts[2]+'|'+parts[3];
 }).filter(Boolean).sort();
 assert.equal(expectedDefs.length,214);assert.deepEqual(observedDefs,expectedDefs,'schema object definition changed');
 const sourceLines=uniqueLines(report,'AX_FUNCTION_SOURCE|');
 assert.equal(sourceLines.length,7,'exactly seven function sources expected');
 const got=new Set();
 for(const line of sourceLines){
  const match=line.match(/^AX_FUNCTION_SOURCE\|([^|]+)\|([0-9a-f]+)$/);
  if(!match||match[2].length%2)throw Error('Malformed function source');
  const name=match[1].split('(')[0];if(!differences.has(name)||got.has(name))throw Error('Unexpected source function');
  got.add(name);
  const actual=canonical(name,tokenize(Buffer.from(match[2],'hex').toString('utf8')));
  assert.deepEqual(actual,functions[name],'SQL function tokens diverged: '+name);
 }
 assert.deepEqual([...got].sort(),[...differences].sort());
 return {rights:observedRights.length,definitions:observedDefs.length,tokenizedFunctions:got.size};
}
if(require.main===module){
 try{
  const report=fs.readFileSync(process.argv[2]||'', 'utf8');
  const defs=fs.readFileSync(path.join(root,'tests/access-x-object-definitions-20261020.txt'),'utf8');
  const rights=fs.readFileSync(path.join(root,'tests/access-x-semantic-rights-20261020.txt'),'utf8');
  const functions=JSON.parse(fs.readFileSync(path.join(root,'tests/access-x-function-tokens-20261020.json'),'utf8'));
  const result=verifyReport(report,defs,rights,functions);
  process.stdout.write('PASS: 72 migrations; '+result.rights+' access scopes; '+result.definitions+' structural definitions; '+result.tokenizedFunctions+' lexical function equivalents.\n');
 }catch(error){process.stderr.write('ACCESS X PARITY BLOCKED: '+error.message+'\n');process.exitCode=1;}
}
module.exports={tokenize,canonical,verifyReport};
