import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { pathToFileURL } from 'node:url';
import { authenticate, applicable, bundle, clean, compare, executionValid, identity, manifest, sign, unpack, verifyBundle, verifyFiles } from '../core.mjs';
import { canonical, command, sha256, write } from '../../releases/core.mjs';

const cases = JSON.parse(fs.readFileSync(new URL('./cases.json',import.meta.url)));
const now = Date.now();
const keys = crypto.generateKeyPairSync('ed25519');
const publicKey = keys.publicKey.export({type:'spki',format:'pem'});
const fixture = () => ({schema:1,repository:'owner/project',tested_sha:'a'.repeat(40),tree:'b'.repeat(40),source_manifest_sha256:'c'.repeat(64),
  controller_hash:'e'.repeat(64),controller_sha:'e'.repeat(40),created_at:new Date(now).toISOString(),
  pr:{number:1,head_sha:'a'.repeat(40),base_sha:'b'.repeat(40)},targets:[{name:'linux-x64',source_sha:'a'.repeat(40),tree:'b'.repeat(40),source_manifest_sha256:'c'.repeat(64),
    fingerprint:'d'.repeat(64),reuse_identity:'exact_commit',result:'success',execution:{kind:'native',os:'linux',arch:'x64'},
    resolved_fingerprint:sha256(canonical({inputs:'d'.repeat(64),execution:{kind:'native',os:'linux',arch:'x64'}})),
    files:['provenance.json','manifest.json','distribution.tar.gz'].map(path => ({path,sha256:'f'.repeat(64)})),logs:[{path:'commands.log',sha256:'f'.repeat(64)}]}]});
for (const scenario of cases.authentication) test(scenario.name,async () => {
  const receipt = fixture();
  if (scenario.age_days) receipt.created_at = new Date(now - scenario.age_days * 86400000).toISOString();
  let envelope;
  try { envelope = scenario.kind === 'signature' ? sign(receipt,'admin-key',keys.privateKey)
    : {receipt,authentication:{kind:scenario.kind,run_id:'123',controller_sha:'e'.repeat(40),bootstrap:scenario.bootstrap || false}}; }
  catch (error) { if (!scenario.valid) return; throw error; }
  if (scenario.tamper) envelope.receipt.tested_sha = 'f'.repeat(40);
  const run = {event:'workflow_dispatch',head_branch:'source',head_sha:'e'.repeat(40),conclusion:'success',path:'.github/workflows/ci.yml',
    head_repository:{full_name:'owner/project'},actor:{login:'admin'},...scenario.run_patch};
  const execute = () => authenticate(envelope,{repository:scenario.repository || 'owner/project',
    keys:{keys:scenario.unknown ? [] : [{id:'admin-key',algorithm:'ed25519',public_key:publicKey,login:'admin',revoked:scenario.revoked || false}]},
    isAdmin:async () => scenario.admin !== false,hostedRun:async () => run,allowBootstrap:async () => scenario.allow_bootstrap === true},now);
  if (scenario.valid) assert.equal((await execute()).validator,'admin');
  else await assert.rejects(execute);
});
for (const scenario of cases.reuse) test(scenario.name,() => {
  const target = fixture().targets[0];
  if (scenario.tree_mode) target.reuse_identity = 'source_tree';
  const entry = {...target,...scenario.patch};
  assert.equal(applicable(target,entry),scenario.valid);
});
for (const scenario of cases.execution) test(scenario.name,() => {
  assert.equal(executionValid({execution:scenario.execution},scenario),scenario.valid);
});
for (const scenario of cases.comparison) test(scenario.name,() => {
  const accepted = fixture(), claim = fixture();
  if (scenario.changed_files) claim.targets[0].files[0].sha256 = '0'.repeat(64);
  if (scenario.reproducible) accepted.targets[0].reproducible = true;
  if (scenario.base_changed) claim.pr.base_sha = 'f'.repeat(40);
  if (scenario.missing_target) claim.targets = [];
  if (scenario.failed_target) claim.targets[0].result = 'failure';
  if (scenario.valid) assert.equal(compare(claim,accepted).length,scenario.differences);
  else assert.throws(() => compare(claim,accepted));
});
test('Git source identities distinguish commits, trees, contents and dirty checkouts',() => {
  const root = path.resolve('build/tests/receipts/source-' + crypto.randomUUID());
  fs.mkdirSync(root,{recursive:true});
  const run = args => command('git',args,{cwd:root}).trim();
  run(['init']);run(['config','user.name','Fixture']);run(['config','user.email','fixture@example.test']);
  for (const file of cases.source_files) write(path.join(root,file.path),file.contents);
  run(['add','.']);run(['commit','-m','First']);
  const first = identity(run(['rev-parse','HEAD']),root);clean(root);
  run(['commit','--allow-empty','-m','Same tree']);
  const second = identity(run(['rev-parse','HEAD']),root);
  assert.notEqual(first.source_sha,second.source_sha);assert.equal(first.tree,second.tree);
  assert.equal(first.source_manifest_sha256,second.source_manifest_sha256);
  for (const file of cases.source_changes) write(path.join(root,file.path),file.contents);
  assert.throws(() => clean(root));run(['add','.']);run(['commit','-m','Changed']);
  assert.notEqual(identity(run(['rev-parse','HEAD']),root).source_manifest_sha256,first.source_manifest_sha256);
});
test('Artifact manifest rejects corruption and extra files',() => {
  const root = path.resolve('build/tests/receipts/files-' + crypto.randomUUID());
  write(path.join(root,'first.txt'),'verified');const expected = manifest(root);verifyFiles(root,expected);
  write(path.join(root,'first.txt'),'corrupt');assert.throws(() => verifyFiles(root,expected));
  write(path.join(root,'first.txt'),'verified');write(path.join(root,'extra.txt'),'extra');assert.throws(() => verifyFiles(root,expected));
});
test('Archive extraction validates ordinary archives and requires fresh destinations',() => {
  const root = path.resolve('build/tests/receipts/archive-' + crypto.randomUUID());
  fs.mkdirSync(root,{recursive:true});write(path.join(root,'file.txt'),'safe');
  command('tar',['-czf',path.join(root,'safe.tar.gz'),'-C',root,'file.txt']);
  unpack(path.join(root,'safe.tar.gz'),path.join(root,'extracted'));
  assert.equal(fs.readFileSync(path.join(root,'extracted/file.txt'),'utf8'),'safe');
  assert.throws(() => unpack(path.join(root,'safe.tar.gz'),path.join(root,'extracted')));
});
for (const scenario of cases.unsafe_archives) test(scenario.name,() => {
  const root = path.resolve('build/tests/receipts/unsafe-' + crypto.randomUUID());fs.mkdirSync(root,{recursive:true});
  const header = Buffer.alloc(512);
  header.write(scenario.path,0);header.write('0000644\0',100);header.write('0000000\0',108);header.write('0000000\0',116);
  header.write('00000000000\0',124);header.write('00000000000\0',136);header.fill(32,148,156);
  header.write(scenario.type,156);if (scenario.link) header.write(scenario.link,157);
  header.write('ustar\0',257);header.write('00',263);
  const sum = header.reduce((sum,byte) => sum + byte,0);header.write(sum.toString(8).padStart(6,'0')+'\0 ',148);
  const archive = path.join(root,'unsafe.tar.gz');fs.writeFileSync(archive,gzipSync(Buffer.concat([header,Buffer.alloc(1024)])));
  assert.throws(() => unpack(archive,path.join(root,'output')));
});
test('Signed PR output restores after a same-tree merge without a build checkout or compiler',() => {
  const root = path.resolve('build/tests/receipts/reuse-' + crypto.randomUUID());fs.mkdirSync(root,{recursive:true});
  const run = args => command('git',args,{cwd:root}).trim();
  run(['init']);run(['config','user.name','Fixture']);run(['config','user.email','fixture@example.test']);
  for (const file of cases.source_files) write(path.join(root,file.path),file.contents);
  run(['add','.']);run(['commit','-m','PR']);const tested = identity(run(['rev-parse','HEAD']),root);
  const artifact = 'distribution-' + tested.source_sha + '-linux-x64';
  const logs = 'build-logs-' + tested.source_sha + '-linux-x64';
  const distributionRoot = path.join(root,'build/distributions',artifact);
  const logRoot = path.join(root,'build/logs',logs);
  const execution = {kind:'container',os:'linux',arch:'x64'};
  const resolved = sha256(canonical({inputs:'d'.repeat(64),execution}));
  write(path.join(distributionRoot,'source-sha.txt'),tested.source_sha+'\n');
  write(path.join(distributionRoot,'provenance.json'),{schema:1,source_sha:tested.source_sha,tree:tested.tree,
    source_manifest_sha256:tested.source_manifest_sha256,fingerprint:'d'.repeat(64),target:'linux-x64',execution,resolved_fingerprint:resolved});
  command('tar',['-czf',path.join(distributionRoot,'distribution.tar.gz'),'-C',distributionRoot,'source-sha.txt']);
  write(path.join(distributionRoot,'manifest.json'),manifest(distributionRoot));write(path.join(logRoot,'build.log'),'independent fixture execution\n');
  const receipt = fixture();receipt.tested_sha = tested.source_sha;receipt.tree = tested.tree;receipt.source_manifest_sha256 = tested.source_manifest_sha256;
  receipt.pr.head_sha = tested.source_sha;receipt.targets = [{...receipt.targets[0],...tested,files:manifest(distributionRoot),logs:manifest(logRoot),
    reuse_identity:'source_tree',artifact,log_artifact:logs,execution,resolved_fingerprint:resolved}];
  const bundled = path.join(root,'build/bundle');bundle(bundled,receipt,path.join(root,'build/distributions'),path.join(root,'build/logs'));verifyBundle(bundled,receipt);
  const archive = path.join(root,'build/bundle.tar.gz');command('tar',['-czf',archive,'-C',bundled,'.']);receipt.bundle_sha256 = sha256(fs.readFileSync(archive));
  const envelope = sign(receipt,'admin-key',keys.privateKey);
  run(['commit','--allow-empty','-m','Merged']);const selected = identity(run(['rev-parse','HEAD']),root);
  const envelopeBytes = Buffer.from(JSON.stringify(envelope));const archiveBytes = fs.readFileSync(archive);
  const release = {id:1,draft:true,tag_name:'ci-validation-fixture',assets:[
    {id:2,name:'receipt.json',size:envelopeBytes.length,digest:'sha256:'+sha256(envelopeBytes)},
    {id:3,name:'bundle.tar.gz',size:archiveBytes.length,digest:'sha256:'+sha256(archiveBytes)}]};
  const stateFile = path.join(root,'build/github.json');
  const state = {keys:{keys:[{id:'admin-key',algorithm:'ed25519',public_key:publicKey,login:'admin'}]},release,
    envelope:envelopeBytes.toString('base64'),archive:archiveBytes.toString('base64')};write(stateFile,state);
  const preload = path.join(root,'build/mock-gh.cjs');
  write(preload,`const cp=require('node:child_process'),fs=require('node:fs');const original=cp.execFileSync;
cp.execFileSync=function(file,args,options={}){if(file!=='gh')return original(file,args,options);
const state=JSON.parse(fs.readFileSync(process.env.RECEIPT_FIXTURE));const endpoint=args[1];let result;
if(endpoint.includes('/collaborators/'))result={permission:'admin'};
else if(endpoint.includes('/contents/ci/receipts/keys.json'))result={content:Buffer.from(JSON.stringify(state.keys)).toString('base64')};
else if(endpoint.endsWith('/releases/assets/2'))result=Buffer.from(state.envelope,'base64');
else if(endpoint.endsWith('/releases/assets/3'))result=Buffer.from(state.archive,'base64');
else if(endpoint.endsWith('/releases/1'))result=state.release;
else if(endpoint.includes('/releases?'))result=[state.release];else throw Error('Unexpected GitHub fixture call: '+endpoint);
const bytes=Buffer.isBuffer(result)?result:Buffer.from(JSON.stringify(result));return options.encoding===null?bytes:bytes.toString();};require('node:module').syncBuiltinESMExports();`);
  const entry = {...receipt.targets[0],...selected,runner:'ubuntu-latest',platform:'linux/amd64',image:'',
    artifact:'distribution-'+selected.source_sha+'-linux-x64'};
  const script = path.join(root,'build/discover.mjs');
  write(script,`import fs from 'node:fs';import {discover} from ${JSON.stringify(pathToFileURL(path.resolve('ci/receipts/github.mjs')).href)};
const plan=JSON.parse(fs.readFileSync('build/plan.json'));const accepted=await discover(plan,null,true);if(accepted.length!==Number(process.env.EXPECT_ACCEPTED))throw Error('Unexpected acceptance');
fs.writeFileSync('build/spec.json',JSON.stringify(plan.builds[0]));`);
  write(path.join(root,'build/plan.json'),{controller_hash:receipt.controller_hash,builds:[entry]});
  const env = {...process.env,GH_REPO:'owner/project',GITHUB_REPOSITORY:'owner/project',RECEIPT_FIXTURE:stateFile,
    NODE_OPTIONS:'--require='+JSON.stringify(preload),EXPECT_ACCEPTED:'1'};
  command(process.execPath,[script],{cwd:root,env});const spec = JSON.parse(fs.readFileSync(path.join(root,'build/spec.json')));
  const prepared = command(process.execPath,[path.resolve('ci/releases/cli.mjs'),'prepare'],{cwd:root,env:{...env,CI_BUILD_SPEC:JSON.stringify(spec)}});
  assert.match(prepared,/Verified cached distribution/);
  assert.equal(fs.readFileSync(path.join(root,'build/artifacts/source-sha.txt'),'utf8').trim(),tested.source_sha);
  assert.equal(JSON.parse(fs.readFileSync(path.join(root,'build/artifacts/provenance.json'))).source_sha,tested.source_sha);
  assert.equal(fs.existsSync(path.join(root,'build/tmp/source',selected.source_sha)),false);
  state.keys.keys[0].revoked = true;write(stateFile,state);
  command(process.execPath,[script],{cwd:root,env:{...env,EXPECT_ACCEPTED:'0'}});
});
