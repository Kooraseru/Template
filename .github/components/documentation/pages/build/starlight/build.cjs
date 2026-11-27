"use strict";
// Legacy documentation build entry point. The shared renderer owns the static build/github/pages output.
const path=require("node:path"),{spawnSync}=require("node:child_process");
const root=path.resolve(__dirname,"../../../../../..");
const loader=path.join(root,"dependencies/packages/core/dependencyLoader/index.ts");
process.env.DOCS_ASSET_MANIFEST ||= 'content/reference-sources/assets.json';
const result=spawnSync(process.execPath,[loader,"--only","tools.documentation","--exec","tools.documentation",...process.argv.slice(2)],{cwd:root,stdio:"inherit",windowsHide:true});
if(result.error)throw result.error;
process.exitCode=result.status??1;
