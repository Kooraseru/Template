"use strict";
const fs=require("node:fs"), path=require("node:path"), {createHash}=require("node:crypto");
const ROOT=path.resolve(__dirname,"../../../..");
const CONTRACT="config/template-contract.json", BOOTSTRAP=".github/workflows/bootstrap.yml";
const REPO=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/, SHA=/^[a-f0-9]{40}$/;
const PATH=/^(?!\/)(?!.*(?:^|\/)\.\.?\/)[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/;
const ENGINE=/uses:\s*Kooraseru-Hub\/CI-Engine\/\.github\/workflows\/bootstrap\.yml@([a-f0-9]{40})/g;
const blobSha=buf=>createHash("sha1").update("blob "+buf.length+"\0").update(buf).digest("hex");
function read(root,name) {
  if(!PATH.test(name))throw Error("Invalid protected path: "+name);
  const f=path.join(root,name), s=fs.lstatSync(f,{throwIfNoEntry:false});
  if(!s||!s.isFile())throw Error("Missing protected file: "+name);
  const resolved=fs.realpathSync(f);
  if(!resolved.startsWith(fs.realpathSync(root)+path.sep))throw Error("Protected path escapes repository: "+name);
  return fs.readFileSync(resolved);
}
function contract(c) {
  if(!c||c.schema!==1||!Array.isArray(c.protected)||c.protected.length<3||
     new Set(c.protected).size!==c.protected.length||
     c.protected.some(p=>typeof p!=="string"||!PATH.test(p))||
     !c.protected.includes(CONTRACT)||
     !c.protected.includes(".github/components/quality/template-conformance/check.cjs")||
     !c.protected.includes(".github/components/quality/template-conformance/component.json"))
    throw Error("Invalid parent template contract");
  return c;
}
function config(root) {
  const c=JSON.parse(read(root,"config/template.json").toString("utf8"));
  if(c.schema!==1||!REPO.test(c.upstream)||!["source","consumer"].includes(c.conformance?.mode))
    throw Error("Invalid template conformance configuration");
  if(c.conformance.mode==="consumer"&&!SHA.test(c.revision||""))
    throw Error("Derived repositories must pin a 40-character parent revision");
  return c;
}
function enginePin(bytes) {
  const pins=[...bytes.toString("utf8").matchAll(ENGINE)];
  if(pins.length!==1)throw Error("Exactly one pinned CI-Engine workflow is required");
  return pins[0][1];
}
async function api(resource,env=process.env,fetcher=globalThis.fetch) {
  const headers={Accept:"application/vnd.github+json","X-GitHub-Api-Version":"2022-11-28",
    "User-Agent":"template-conformance"};
  const token=env.GH_TOKEN||env.GITHUB_TOKEN;
  if(token)headers.Authorization="Bearer "+token;
  const r=await fetcher("https://api.github.com/repos/"+resource,
    {headers,signal:AbortSignal.timeout(20000)});
  if(!r.ok)throw Error("Parent verification HTTP "+r.status+": "+resource);
  return r.json();
}
async function check({root=ROOT,env=process.env,get=resource=>api(resource,env)}={}) {
  const settings=config(root), localBytes=read(root,CONTRACT);
  const localContract=contract(JSON.parse(localBytes.toString("utf8")));
  if(settings.conformance.mode==="source") {
    if(env.GITHUB_REPOSITORY&&env.GITHUB_REPOSITORY.toLowerCase()!==settings.upstream.toLowerCase())
      throw Error("Source mode forbidden outside upstream repository");
    for(const p of localContract.protected)read(root,p);
    return {state:"source",upstream:settings.upstream,protected:localContract.protected.length,mismatches:[]};
  }
  if(env.GITHUB_REPOSITORY?.toLowerCase()===settings.upstream.toLowerCase())
    throw Error("Consumer mode cannot target its own repository");
  const upstream=settings.upstream,revision=settings.revision;
  const tree=await get(upstream+"/git/trees/"+revision+"?recursive=1");
  if(!tree||tree.truncated||!Array.isArray(tree.tree))
    throw Error("Incomplete immutable parent tree");
  const blobs=new Map(tree.tree.filter(x=>x.type==="blob").map(x=>[x.path,x.sha]));
  async function parentFile(name) {
    const r=await get(upstream+"/contents/"+name+"?ref="+revision);
    if(!r||r.encoding!=="base64"||typeof r.content!=="string")
      throw Error("Invalid parent content response: "+name);
    const bytes=Buffer.from(r.content.replace(/\s+/g,""),"base64");
    if(blobSha(bytes)!==blobs.get(name))throw Error("Parent content differs from pinned Git tree: "+name);
    return bytes;
  }
  const parent=contract(JSON.parse((await parentFile(CONTRACT)).toString("utf8")));
  const mismatches=[];
  if(blobSha(localBytes)!==blobs.get(CONTRACT))mismatches.push(CONTRACT);
  for(const name of parent.protected) {
    if(name===CONTRACT)continue;
    if(!SHA.test(blobs.get(name)||""))throw Error("Parent missing protected file: "+name);
    try {if(blobSha(read(root,name))!==blobs.get(name))mismatches.push(name);}
    catch {mismatches.push(name);}
  }
  if(enginePin(read(root,BOOTSTRAP))!==enginePin(await parentFile(BOOTSTRAP)))
    mismatches.push(BOOTSTRAP+" (CI-Engine pin)");
  const latest=await get(upstream+"/branches/source"),head=latest?.commit?.sha;
  if(!SHA.test(head||""))throw Error("Cannot resolve upstream source branch");
  return {state:mismatches.length?"diverged":(head===revision?"current":"conformant-upstream-different"),
    upstream,revision,upstreamHead:head,protected:parent.protected.length,mismatches};
}
function report(r) {
  const lines=["## Template conformance","","Parent: "+r.upstream,"Status: "+r.state,
    "Protected files: "+r.protected];
  if(r.revision)lines.push("Pinned revision: "+r.revision);
  if(r.upstreamHead)lines.push("Parent source revision: "+r.upstreamHead);
  if(r.mismatches.length)lines.push("Divergences:",...r.mismatches.map(x=>"- "+x));
  if(r.state==="conformant-upstream-different")
    lines.push("The pinned parent conforms, but source has moved; review upstream before repinning.");
  return lines.join("\n")+"\n";
}
async function main() {
  const r=await check(),summary=report(r);
  process.stdout.write(summary);
  if(process.env.GITHUB_STEP_SUMMARY)fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,summary);
  if(r.mismatches.length)process.exitCode=1;
}
module.exports={blobSha,read,contract,config,enginePin,api,check,report,main};
if(require.main===module)main().catch(e=>{console.error("::error::Template conformance: "+e.message);process.exitCode=1;});
