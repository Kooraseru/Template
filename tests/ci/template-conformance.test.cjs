"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs"),os=require("node:os"),path=require("node:path");
const {check,blobSha,contract,enginePin}=require("../../.github/components/quality/template-conformance/check.cjs");
const U="Example/Parent",REV="a".repeat(40),PIN="b".repeat(40);
const C="config/template-contract.json",B=".github/workflows/bootstrap.yml";
const X=".github/components/quality/template-conformance/check.cjs";
const Y=".github/components/quality/template-conformance/component.json";
function fixture(t,mode="consumer"){
 const root=fs.mkdtempSync(path.join(os.tmpdir(),"conformance-"));
 t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const files=new Map();
 function put(name,value){
  const b=Buffer.from(value),f=path.join(root,name);
  fs.mkdirSync(path.dirname(f),{recursive:true});
  fs.writeFileSync(f,b);files.set(name,b);
 }
 put(C,JSON.stringify({schema:1,protected:[C,X,Y]}));
 put(X,"checker");put(Y,"component");
 put(B,"uses: Kooraseru-Hub/CI-Engine/.github/workflows/bootstrap.yml@"+PIN+"\n");
 put("config/template.json",JSON.stringify({schema:1,upstream:U,
  revision:mode==="source"?null:REV,conformance:{mode}}));
 const source=new Map(files);
 async function get(uri){
  if(uri===U+"/git/trees/"+REV+"?recursive=1")
   return {tree:[...source].filter(([p])=>p!=="config/template.json")
    .map(([p,b])=>({path:p,sha:blobSha(b),type:"blob"}))};
  if(uri.startsWith(U+"/contents/")){
   const name=uri.slice((U+"/contents/").length).split("?ref=")[0];
   return {encoding:"base64",content:source.get(name).toString("base64")};
  }
  if(uri===U+"/branches/source")return {commit:{sha:REV}};
  throw Error("Unknown mock request: "+uri);
 }
 return {root,put,get};
}
test("source validates locally",async t=>{
 const {root,get}=fixture(t,"source");
 assert.equal((await check({root,get,env:{GITHUB_REPOSITORY:U}})).state,"source");
});
test("consumer matches pinned parent and engine",async t=>{
 const {root,get}=fixture(t);
 assert.equal((await check({root,get})).state,"current");
});
test("protected drift fails",async t=>{
 const {root,get}=fixture(t);
 fs.writeFileSync(path.join(root,X),"tampered");
 assert.deepEqual((await check({root,get})).mismatches,[X]);
});
test("upstream movement is not claimed current",async t=>{
 const {root,get}=fixture(t);
 const x=await check({root,get:uri=>uri.endsWith("/branches/source")
   ?{commit:{sha:"c".repeat(40)}}:get(uri)});
 assert.equal(x.state,"conformant-upstream-different");
});
test("consumer must have immutable revision",async t=>{
 const {root,put,get}=fixture(t);
 put("config/template.json",JSON.stringify({schema:1,upstream:U,
  revision:null,conformance:{mode:"consumer"}}));
 await assert.rejects(check({root,get}),/40-character/);
});
test("invalid contract and source mode spoofing fail",async t=>{
 const {root,put,get}=fixture(t,"source");
 assert.throws(()=>contract({schema:1,protected:[C,X,Y,"../escape"]}),/Invalid parent/);
 await assert.rejects(check({root,get,env:{GITHUB_REPOSITORY:"Other/Repo"}}),/forbidden/);
});
test("network errors do not silently pass",async t=>{
 const {root}=fixture(t);
 await assert.rejects(check({root,get:()=>{throw Error("Network down");}}),/Network down/);
});
test("exactly one CI-Engine pin",()=>{
 const b=Buffer.from("uses: Kooraseru-Hub/CI-Engine/.github/workflows/bootstrap.yml@"+PIN);
 assert.equal(enginePin(b),PIN);
 assert.throws(()=>enginePin(Buffer.concat([b,b])),/Exactly one/);
});
