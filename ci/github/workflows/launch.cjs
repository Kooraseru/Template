"use strict";
// Create a build-only native pipeline from a trusted default-branch push.
// Write credentials are never passed into the resulting workflow jobs.
const fs = require("node:fs");
const crypto = require("node:crypto");
const { render } = require("./preview.cjs");
const SHA=/^[0-9a-f]{40}$/;
const REPO=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const BRANCH=/^[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));

function context(env=process.env){
  if(env.GITHUB_ACTIONS!=="true"||!["push","workflow_dispatch"].includes(env.GITHUB_EVENT_NAME)||
    !env.CI_DEFAULT_BRANCH||!BRANCH.test(env.CI_DEFAULT_BRANCH)||
    env.CI_DEFAULT_BRANCH.includes("..")||
    env.GITHUB_REF!=="refs/heads/"+env.CI_DEFAULT_BRANCH){
    throw new Error("Native generation requires a trusted default-branch push or manual validation dispatch");
  }
  if(!REPO.test(env.GITHUB_REPOSITORY||"")||!SHA.test(env.GITHUB_SHA||"")||
     !/^[1-9]\d*$/.test(env.GITHUB_RUN_ID||"")||
     !/^[1-9]\d*$/.test(env.GITHUB_RUN_ATTEMPT||"")){
    throw new Error("Invalid native CI repository or run identity");
  }
  if(env.CI_NATIVE_PUBLISH==="true"||env.CI_PUBLICATION_ENABLED==="true"){
    throw new Error("Native validation cannot publish");
  }
  return {repo:env.GITHUB_REPOSITORY,sha:env.GITHUB_SHA,
    branch:"ci/run-push-"+env.GITHUB_RUN_ID+"-"+env.GITHUB_RUN_ATTEMPT+"-"+env.GITHUB_SHA.slice(0,10)};
}

async function api(method,resource,token,body,env=process.env){
  if(!token)throw new Error("Missing authenticated GitHub API token");
  const root=new URL(env.GITHUB_API_URL||"https://api.github.com");
  if(root.protocol!=="https:"||root.username||root.password)throw new Error("GitHub API must use HTTPS");
  const url=root.toString().replace(/\/+$/,"")+resource;
  const response=await fetch(url,{
    method,
    headers:{
      Authorization:"Bearer "+token,
      Accept:"application/vnd.github+json",
      "Content-Type":"application/json",
      "X-GitHub-Api-Version":"2022-11-28",
      "User-Agent":"template-native-ci",
    },
    body:body===undefined?undefined:JSON.stringify(body),
    signal:AbortSignal.timeout(30000)
  });
  let result=null;
  try{result=await response.json()}catch{}
  if(!response.ok){
    throw new Error(method+" "+resource.split("?")[0]+" HTTP "+response.status+
      (response.status===403?" (verify Contents: write, Workflows: write, Actions: read)":""));
  }
  return result;
}

function signJWT(id,key){
  if(!/^\d+$/.test(id))throw new Error("Invalid GitHub App ID");
  const now=Math.floor(Date.now()/1000);
  const encoded=x=>Buffer.from(JSON.stringify(x)).toString("base64url");
  const body=encoded({alg:"RS256",typ:"JWT"})+"."+
    encoded({iat:now-30,exp:now+480,iss:id});
  return body+"."+crypto.sign("RSA-SHA256",Buffer.from(body),key).toString("base64url");
}

function requiredAppPermissions(granted){
  const required={contents:"write",workflows:"write"};
  const missing=Object.entries(required).filter(([key,access])=>granted?.[key]!==access).map(([key,access])=>key+":"+access);
  if(missing.length)throw new Error("GitHub App installation missing required permissions: "+missing.join(", ")+
    ". Update the App permissions and approve the installation change.");
  return required;
}

async function writerToken(repo,env=process.env){
  if(env.CI_NATIVE_APP_ID&&env.CI_NATIVE_APP_PRIVATE_KEY){
    const signed=signJWT(env.CI_NATIVE_APP_ID,env.CI_NATIVE_APP_PRIVATE_KEY);
    const installation=await api("GET","/repos/"+repo+"/installation",signed,undefined,env);
    if(!Number.isSafeInteger(installation?.id))throw new Error("GitHub App installation ID missing");
    const permissions=requiredAppPermissions(installation.permissions);
    const token=await api("POST","/app/installations/"+installation.id+"/access_tokens",signed,{
      repositories:[repo.split("/")[1]],
      permissions,
    },env);
    if(!token?.token)throw new Error("GitHub App returned no installation token");
    console.log("::add-mask::"+token.token);
    return token.token;
  }
  if(env.CI_NATIVE_WRITE_TOKEN&&env.CI_NATIVE_WRITE_TOKEN!==env.CI_NATIVE_READ_TOKEN){
    console.log("::add-mask::"+env.CI_NATIVE_WRITE_TOKEN);
    return env.CI_NATIVE_WRITE_TOKEN;
  }
  throw new Error("Configure CI_APP_ID and CI_APP_PRIVATE_KEY, or CI_TOKEN with Contents/Workflows write, for native builds");
}

async function createBranch(ctx,files,token,env=process.env){
  const base="/repos/"+ctx.repo;
  const parent=await api("GET",base+"/git/commits/"+ctx.sha,token,undefined,env);
  if(!SHA.test(parent?.tree?.sha||""))throw new Error("Source commit tree unavailable");
  const entries=[];
  for(const [name,content] of Object.entries(files)){
    if(!/^[a-z][a-z0-9-]*\.yml$/.test(name))throw new Error("Unsafe generated workflow name");
    const blob=await api("POST",base+"/git/blobs",token,{content,encoding:"utf-8"},env);
    if(!SHA.test(blob?.sha||""))throw new Error("Workflow blob creation failed");
    entries.push({path:".github/workflows/"+name,type:"blob",mode:"100644",sha:blob.sha});
  }
  entries.push({path:".github/workflows/ci.yml",type:"blob",mode:"100644",sha:null});
  const tree=await api("POST",base+"/git/trees",token,{base_tree:parent.tree.sha,tree:entries},env);
  if(!SHA.test(tree?.sha||""))throw new Error("Generated tree creation failed");
  const commit=await api("POST",base+"/git/commits",token,{
    message:"ci(generated): native build for "+ctx.sha,
    tree:tree.sha,parents:[ctx.sha]
  },env);
  if(!SHA.test(commit?.sha||""))throw new Error("Generated commit creation failed");
  await api("POST",base+"/git/refs",token,{ref:"refs/heads/"+ctx.branch,sha:commit.sha},env);
  return commit.sha;
}

async function observe(ctx,commit,token,env=process.env,delay=sleep){
  const base="/repos/"+ctx.repo;
  const beginning=Date.now(),startDeadline=beginning+180000,deadline=beginning+3600000;
  let id=null,link=null;
  while(Date.now()<deadline){
    const response=await api("GET",id?base+"/actions/runs/"+id:
      base+"/actions/runs?branch="+encodeURIComponent(ctx.branch)+"&event=push&per_page=30",token,undefined,env);
    const list=id?[response]:response?.workflow_runs;
    if(!Array.isArray(list))throw new Error("Invalid generated run response");
    const run=list.find(item=>item&&item.head_branch===ctx.branch&&item.head_sha===commit&&
      (item.path===".github/workflows/pipeline.yml"||
       item.path===".github/workflows/pipeline.yml@refs/heads/"+ctx.branch));
    if(run){
      id=run.id;link=run.html_url;
      if(!Number.isSafeInteger(id))throw new Error("Generated workflow has no run ID");
      if(run.status==="completed"){
        if(run.conclusion!=="success")throw new Error("Native build "+run.conclusion+": "+link);
        return {id,link};
      }
    }else if(!id&&Date.now()>startDeadline){
      throw new Error("Generated workflow was not scheduled; a GitHub App/PAT push token is required");
    }
    await delay(8000);
  }
  throw new Error("Native build timed out"+(link?": "+link:""));
}

async function run(env=process.env){
  const ctx=context(env);
  const files=render(ctx.branch,ctx.sha,undefined,"push");
  // Validate the entire build-only graph before minting a write credential.
  const token=await writerToken(ctx.repo,env);
  const revision=await createBranch(ctx,files,token,env);
  console.log("::notice::Created build-only branch "+ctx.branch);
  const result=await observe(ctx,revision,env.CI_NATIVE_READ_TOKEN||token,env);
  if(env.GITHUB_STEP_SUMMARY){
    fs.appendFileSync(env.GITHUB_STEP_SUMMARY,
      "\n### Native build\n\nSource: "+ctx.sha+"\nBranch: "+ctx.branch+
      "\nRun: "+result.link+"\nPublication: disabled\n");
  }
  console.log("::notice::Native pipeline passed: "+result.link);
  return {...ctx,...result};
}
module.exports={context,api,signJWT,requiredAppPermissions,writerToken,createBranch,observe,run};
if(require.main===module)run().catch(error=>{
  console.error("::error::"+String(error.message||error));process.exitCode=1;
});
