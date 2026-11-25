"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {sync}=require("./summary.cjs");
const repository="owner/repo",sha="a".repeat(40),pr="42",marker="<!-- template-ci:documentation-preview:v1 -->";
function fixture(){
 const comments=[],writes=[];
 const request=async(method,url,body)=>{
  if(method==="GET"&&url.includes("/pulls/"))return {state:"open",head:{sha},base:{repo:{full_name:repository}}};
  if(method==="GET"&&url.includes("/actions/runs/"))return [{jobs:[{name:"documentation",conclusion:"failure"},{name:"validate",conclusion:"success"}]}];
  if(method==="GET")return comments;
  writes.push(method);
  if(method==="POST")comments.push({id:2,user:{id:41898282},body:body.body});
  else comments.find(x=>x.id===2).body=body.body;
 };
 return {comments,writes,request};
}
test("one bot comment from intake to validated preview",async()=>{
 const f=fixture(),base={repository,sha,pr};
 await sync({...base,status:"pending"},f.request);
 assert.match(f.comments[0].body,/Pending validation/);
 f.comments[0].body=marker+"\n**Website:** [Open preview](https://pr-42.example.pages.dev/owner/repo/)\n**Revision:** ["+sha.slice(0,12)+"](https://github.com/"+repository+"/commit/"+sha+")";
 await sync({...base,status:"success",run:"123"},f.request);
 assert.match(f.comments[0].body,/Open preview/);
 assert.match(f.comments[0].body,/What needs your attention/);
 await sync({...base,status:"pending"},f.request);
 assert.deepEqual(f.writes,["POST","PATCH"]);
});
test("never reuse stale preview or change human comment",async()=>{
 const f=fixture();
 f.comments.push({id:1,user:{id:9},body:marker});
 await sync({repository,sha,pr,status:"failure",run:"123"},f.request);
 assert.equal(f.comments[0].body,marker);
 assert.doesNotMatch(f.comments[1].body,/pages\.dev/);
 assert.match(f.comments[1].body,/Address failed checks/);
 assert.match(f.comments[1].body,/Failed jobs: `documentation`/);
});
