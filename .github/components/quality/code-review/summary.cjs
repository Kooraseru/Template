"use strict";
const { execFileSync } = require("node:child_process");
const MARKER = "<!-- template-ci:documentation-preview:v1 -->";
const SHA = /^[a-f0-9]{40}$/;
function owned(comment) {
  return Number.isSafeInteger(comment?.id) && comment.user?.id === 41898282 &&
    typeof comment.body === "string" && comment.body.includes(MARKER);
}
function deployed(body, repository, sha) {
  if (!body || !SHA.test(sha)) return null;
  const revision = body.match(/\*\*Revision:\*\* \[[a-f0-9]{12}\]\((https:\/\/github\.com\/[^)]+)\)/);
  const link = body.match(/\*\*Website:\*\* \[Open preview\]\((https:\/\/[a-z0-9.-]+\.pages\.dev\/[A-Za-z0-9._~/-]*)\)/);
  return revision?.[1] === "https://github.com/" + repository + "/commit/" + sha && link ? link[1] : null;
}
function render({repository,sha,status,run,preview,reviewResult,previewResult,failedJobs=[]}) {
  const rows=[MARKER,"## PR summary","", "**Revision:** ["+sha.slice(0,12)+"](https://github.com/"+repository+"/commit/"+sha+")"];
  rows.push("**CI:** "+({pending:"Pending",success:"Passed",failure:"Failed"}[status]));
  if(run)rows.push("**Checks:** [Open workflow results](https://github.com/"+repository+"/actions/runs/"+run+")");
  rows.push("", "### Documentation preview");
  if(preview)rows.push("**Website:** [Open preview]("+preview+")");
  else if(previewResult==="failure")rows.push("Deployment failed. Inspect the PR Results workflow before reviewing the site.");
  else rows.push(status==="failure"?"Not updated because validation failed.":status==="pending"?"Pending validation and deployment.":"No current preview confirmed; see workflow results.");
  rows.push("","### What needs your attention");
  if(status==="pending")rows.push("- Review the changes once validation completes.");
  else if(status==="failure")rows.push("- Address failed checks and any unresolved inline review findings.");
  else rows.push("- Review the changes and any unresolved inline review findings.");
  if(failedJobs.length)rows.push("- Failed jobs: "+failedJobs.map(name=>"`"+name.replace(/[^A-Za-z0-9 _.,():/-]/g," ").slice(0,160)+"`").join(", ")+".");
  if(reviewResult==="failure")rows.push("- Automated review failed; inspect the PR Results workflow.");
  if(previewResult==="failure")rows.push("- Investigate the preview deployment failure.");
  if(preview)rows.push("- Inspect the rendered documentation before merging.");
  rows.push("- Merge when the changes are acceptable.","","This summary is maintained by CI.");
  return rows.join("\n");
}
async function sync({repository,pr,sha,status,run,reviewResult,previewResult},request) {
  if(!/^[\w.-]+\/[\w.-]+$/.test(repository)||!/^\d+$/.test(pr)||!SHA.test(sha)||
    !["pending","success","failure"].includes(status)||(run&&!/^\d+$/.test(run)))throw Error("Invalid PR summary context");
  const base="/repos/"+repository;
  const current=async()=>{const p=await request("GET",base+"/pulls/"+pr);return p.state==="open"&&p.head.sha===sha&&p.base.repo.full_name===repository;};
  if(!await current())return;
  const list=await request("GET",base+"/issues/"+pr+"/comments?per_page=100",undefined,true);
  const previous=list.find(owned);
  const preview=deployed(previous?.body,repository,sha);
  // Never regress a completed summary if an intake event is delayed.
  if(status==="pending"&&(preview||previous?.body.includes("/commit/"+sha+")")&&/\*\*CI:\*\* (Passed|Failed)/.test(previous.body)))return;
  const failedJobs=[];
  if(status==="failure"&&run){
    const pages=await request("GET",base+"/actions/runs/"+run+"/jobs?per_page=100",undefined,true);
    for(const item of pages.flatMap(page=>page.jobs||[]))if(item.conclusion==="failure"&&typeof item.name==="string")failedJobs.push(item.name);
  }
  const body=render({repository,sha,status,run,preview,reviewResult,previewResult,failedJobs});
  if(!await current()||previous?.body===body)return;
  if(previous)await request("PATCH",base+"/issues/comments/"+previous.id,{body});
  else await request("POST",base+"/issues/"+pr+"/comments",{body});
}
function api(method,endpoint,body,paginate=false){
  const args=["api","--method",method,endpoint,...(paginate?["--paginate","--slurp"]:[]),...(body?["--input","-"]:[])];
  const result=JSON.parse(execFileSync("gh",args,{encoding:"utf8",input:body?JSON.stringify(body):undefined,timeout:45000,maxBuffer:8*1024*1024}));
  return paginate?result.flat():result;
}
module.exports={sync,render,deployed,owned};
if(require.main===module)sync({repository:process.env.GITHUB_REPOSITORY,pr:process.env.PR_NUMBER,sha:process.env.REQUEST_SHA,status:process.env.CI_STATUS,run:process.env.CI_RUN_ID,reviewResult:process.env.REVIEW_RESULT,previewResult:process.env.PREVIEW_RESULT},api).catch(e=>{console.error(e.message);process.exitCode=1});
