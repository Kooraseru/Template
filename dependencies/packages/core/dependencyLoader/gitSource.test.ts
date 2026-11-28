import test from "node:test";
import assert from "node:assert/strict";
import {gitSource,gitSourceOptions} from "./gitSource.ts";
const options={repository:"example/tools",commit:"a".repeat(40),sourcePath:"packages/docs",packagePath:"packages/docs",entry:"build.cjs"};
test("Git source requires immutable commits and contained paths",()=>{
    assert.equal(gitSourceOptions(options).commit,options.commit);
    assert.throws(()=>gitSourceOptions({...options,commit:"main"}),/immutable/);
    assert.throws(()=>gitSourceOptions({...options,repository:"https://example.invalid/repo"}),/owner\/repository/);
    assert.throws(()=>gitSourceOptions({...options,sourcePath:"../escape"}),/Unsafe relative path/);
});
test("Git source resolution is offline and locks the exact repository and source",async()=>{
    const request={action:"resolve" as const,id:"tool.docs",options,workspace:".",stage:".",platform:process.platform,arch:process.arch,prerequisites:{}};
    assert.deepEqual(await gitSource.resolve(request),{repository:options.repository,commit:options.commit,sourcePath:options.sourcePath});
    assert.throws(()=>gitSource.install({...request,action:"install",resolution:{commit:"b".repeat(40)}}),/lock does not match/);
});
