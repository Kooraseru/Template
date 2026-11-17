"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {context,signJWT,requiredAppPermissions,createBranch,observe,deleteBranch}=require("./launch.cjs");
const SHA="a".repeat(40);
const trusted=()=>({
  GITHUB_ACTIONS:"true",GITHUB_EVENT_NAME:"push",
  GITHUB_REF:"refs/heads/source",CI_DEFAULT_BRANCH:"source",
  GITHUB_REPOSITORY:"Kooraseru/Template",GITHUB_SHA:SHA,
  GITHUB_RUN_ID:"1234",GITHUB_RUN_ATTEMPT:"2",
});
test("trusted push gets a deterministic, attempt-specific native branch",()=>{
  const x=context(trusted());
  assert.equal(x.branch,"ci/run-push-1234-2-"+SHA.slice(0,10));
  assert.equal(context({...trusted(),GITHUB_EVENT_NAME:"workflow_dispatch"}).branch,x.branch);
  const {render}=require("./preview.cjs");
  const files=render(x.branch,x.sha,undefined,"push");
  assert.deepEqual(Object.keys(files).sort(),[
    "build.yml","distribution.yml","pipeline.yml","plan.yml","quality.yml","tests.yml"
  ]);
  for(const source of Object.values(files)){
    assert.doesNotMatch(source,/id-token: write|secrets: inherit|pull_request_target:|\/publish/);
  }
});
test("untrusted refs, pull requests, and publication intent fail closed",()=>{
  for(const change of [
    {GITHUB_EVENT_NAME:"pull_request"},
    {GITHUB_EVENT_NAME:"repository_dispatch"},
    {GITHUB_REF:"refs/heads/topic"},
    {CI_DEFAULT_BRANCH:"../source"},
    {GITHUB_REF:"refs/heads/ci/run-push-123-1-aaaaaaaa"},
    {GITHUB_REPOSITORY:"not-a-repository"},
    {GITHUB_RUN_ID:"123/evil"},
    {CI_NATIVE_PUBLISH:"true"},
    {CI_PUBLICATION_ENABLED:"true"},
  ]){
    assert.throws(()=>context({...trusted(),...change}));
  }
});
test("native GitHub App token scopes only to workflow writing and repository contents",()=>{
  const permissions=requiredAppPermissions({contents:"write",workflows:"write",metadata:"read"});
  assert.deepEqual(permissions,{contents:"write",workflows:"write"});
  assert.equal(permissions.actions,undefined);
  assert.throws(()=>requiredAppPermissions({contents:"write",actions:"read"}),/workflows:write/);
  assert.throws(()=>requiredAppPermissions({workflows:"write",contents:"read"}),/contents:write/);
});
test("GitHub App token signing does not accept malformed app identities",()=>{
  assert.throws(()=>signJWT("not-an-app-id","bad key"),/Invalid GitHub App ID/);
});
test("generated commit includes only read-only workflows and removes permanent launcher",async()=>{
  const calls=[];
  const saved=global.fetch;
  const parent={tree:{sha:"b".repeat(40)}};
  let order=0;
  const response=body=>({ok:true,json:async()=>body});
  global.fetch=async(url,args)=>{
    const path=new URL(url).pathname;
    calls.push({path,method:args.method,body:args.body&&JSON.parse(args.body)});
    if(path.endsWith("/git/commits/"+SHA))return response(parent);
    if(path.endsWith("/git/trees/"+"b".repeat(40)))return response({tree:["manual.yml","pull.yml","push.yml","remote.yml","actions.lock"].map(name=>({type:"blob",path:".github/workflows/"+name}))});
    if(path.endsWith("/git/blobs"))return response({sha:"c".repeat(40)});
    if(path.endsWith("/git/trees"))return response({sha:"d".repeat(40)});
    if(path.endsWith("/git/commits"))return response({sha:"e".repeat(40)});
    if(path.endsWith("/git/refs"))return response({});
    throw Error("Unexpected API call "+path);
  };
  try{
    const ctx=context(trusted());
    const result=await createBranch(ctx,{
      "pipeline.yml":"name: Generated CI\non:\n  push:\n",
      "tests.yml":"name: Tests\non:\n  workflow_call:\n",
    },"scoped-writer",{GITHUB_API_URL:"https://api.github.com"});
    assert.equal(result,"e".repeat(40));
    const tree=calls.find(c=>c.path.endsWith("/git/trees")).body.tree;
    assert.deepEqual(tree.map(x=>x.path).sort(),[
      ".github/workflows/manual.yml",".github/workflows/pipeline.yml",".github/workflows/pull.yml",".github/workflows/push.yml",".github/workflows/remote.yml",".github/workflows/tests.yml"
    ]);
    for(const name of ["manual","pull","push","remote"])assert.equal(tree.find(x=>x.path.endsWith("/"+name+".yml")).sha,null);
    assert.deepEqual(calls.find(c=>c.path.endsWith("/git/refs")).body,{
      ref:"refs/heads/"+ctx.branch,sha:"e".repeat(40)
    });
  }finally{global.fetch=saved}
});
test("generated run verifies exact branch, source commit and success",async()=>{
  const ctx=context(trusted()), revision="f".repeat(40);
  const saved=global.fetch;
  let checks=0;
  global.fetch=async()=>{
    checks++;
    return {ok:true,json:async()=>({workflow_runs:[{
      head_branch:ctx.branch,head_sha:revision,path:".github/workflows/pipeline.yml",
      id:123,status:"completed",conclusion:"success",html_url:"https://github.com/org/repo/actions/runs/123"
    }]})};
  };
  try{
    const r=await observe(ctx,revision,"read-token",{},async()=>{});
    assert.equal(r.id,123);assert.equal(checks,1);
  }finally{global.fetch=saved}
});

test("cleanup deletes only generated branch refs using the write credential",async()=>{
  const saved=global.fetch;
  const calls=[];
  global.fetch=async(url,args)=>{
    calls.push({url,method:args.method,auth:args.headers.Authorization});
    return {ok:true,json:async()=>({})};
  };
  try{
    const ctx=context(trusted());
    await deleteBranch(ctx,"write-token",{});
    assert.equal(calls.length,1);
    assert.equal(calls[0].method,"DELETE");
    assert.equal(calls[0].auth,"Bearer write-token");
    assert.equal(new URL(calls[0].url).pathname,
      "/repos/Kooraseru/Template/git/refs/heads/"+ctx.branch);
    await assert.rejects(deleteBranch({...ctx,branch:"source"},"write-token",{}),/Refusing to delete/);
    assert.equal(calls.length,1);
  }finally{global.fetch=saved}
});
