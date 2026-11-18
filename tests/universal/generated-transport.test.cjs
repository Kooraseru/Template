"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {signJWT,requiredAppPermissions,createBranch,observe}=require("../../dependencies/managed/packages/ci-engine/src/native/github/workflows/launch.cjs");
const SHA="a".repeat(40);
const ctx={repo:"Kooraseru/Template",sha:SHA,branch:"ci/run-preview-1234-2-"+SHA.slice(0,10)};
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
test("generated deployment commit removes event callers and preserves the engine pin",async()=>{
  const calls=[];
  const saved=global.fetch;
  const parent={tree:{sha:"b".repeat(40)}};
  let order=0;
  const response=body=>({ok:true,json:async()=>body});
  global.fetch=async(url,args)=>{
    const path=new URL(url).pathname;
    calls.push({path,method:args.method,body:args.body&&JSON.parse(args.body)});
    if(path.endsWith("/git/commits/"+SHA))return response(parent);
    if(path.endsWith("/git/trees/"+"b".repeat(40)))return response({tree:["bootstrap.yml","manual.yml","pull.yml","push.yml","remote.yml","actions.lock"].map(name=>({type:"blob",path:".github/workflows/"+name}))});
    if(path.endsWith("/git/blobs"))return response({sha:"c".repeat(40)});
    if(path.endsWith("/git/trees"))return response({sha:"d".repeat(40)});
    if(path.endsWith("/git/commits"))return response({sha:"e".repeat(40)});
    if(path.endsWith("/git/refs"))return response({});
    throw Error("Unexpected API call "+path);
  };
  try{
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
    assert.ok(!tree.some(x=>x.path.endsWith("/bootstrap.yml")));
    assert.deepEqual(calls.find(c=>c.path.endsWith("/git/refs")).body,{
      ref:"refs/heads/"+ctx.branch,sha:"e".repeat(40)
    });
  }finally{global.fetch=saved}
});
test("generated run verifies exact branch, source commit and success",async()=>{
  const revision="f".repeat(40);
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
