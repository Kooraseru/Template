import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { contained, relativePath, type Provider, type RecordValue } from "./contract.ts";

export function gitSourceOptions(options: RecordValue) {
    const repository = options.repository, commit = options.commit;
    if (typeof repository !== "string" || !/^[A-Za-z0-9_-][A-Za-z0-9_.-]*\/[A-Za-z0-9_-][A-Za-z0-9_.-]*$/.test(repository))
        throw new Error("Expected a GitHub owner/repository");
    if (typeof commit !== "string" || !/^[a-f0-9]{40}$/.test(commit))
        throw new Error("Git source requires an immutable commit SHA");
    return { repository, commit, sourcePath: relativePath(options.sourcePath),
        packagePath: relativePath(options.packagePath), entry: options.entry === undefined ? undefined : relativePath(options.entry) };
}
function git(directory: string, args: string[]) {
    const result=spawnSync("git", ["-C",directory,...args], { encoding:"utf8", windowsHide:true, timeout:90000,
        env:{...process.env,GIT_TERMINAL_PROMPT:"0"} });
    if(result.error)throw result.error;
    if(result.status!==0)throw new Error("git "+args[0]+" failed: "+result.stderr.trim());
    return result.stdout.trim();
}
export const gitSource: Provider = {
    resolve({options}) {
        const {repository,commit,sourcePath}=gitSourceOptions(options);
        return {repository,commit,sourcePath};
    },
    install({options,resolution,stage}) {
        const {repository,commit,sourcePath,packagePath,entry}=gitSourceOptions(options);
        assert.deepEqual(resolution,{repository,commit,sourcePath},"Git source lock does not match requested commit");
        const checkout=path.join(stage,"checkout");
        fs.mkdirSync(checkout);
        git(checkout,["init","--quiet","--template="]);
        git(checkout,["fetch","--quiet","--no-tags","--depth=1","https://github.com/"+repository+".git",commit]);
        git(checkout,["checkout","--quiet","--detach","FETCH_HEAD"]);
        assert.equal(git(checkout,["rev-parse","HEAD"]),commit,"Fetched Git revision differs");
        const source=contained(checkout,sourcePath);
        assert(fs.statSync(source).isDirectory(),"Git source package must be a directory");
        fs.cpSync(source,path.join(stage,"output"),{recursive:true});
        return {outputs:[{from:"output",to:packagePath}],exports:{
            source:{root:"managed",path:packagePath},
            ...(entry?{cli:{root:"managed",path:packagePath+"/"+entry}}:{})
        },...(entry?{executable:{export:"cli",interpreter:["node"]}}:{})};
    }
};
