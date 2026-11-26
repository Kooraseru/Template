"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const id=/^[a-z][a-z0-9-]*$/;
function discover(root) {
    const entries=fs.readdirSync(root,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name));
    const experiments=entries.map(entry=>{
        assert(entry.isDirectory()&&id.test(entry.name),"Invalid experiment: "+entry.name);
        const directory=path.join(root,entry.name), manifest=path.join(directory,"experiment.json");
        assert(fs.lstatSync(manifest).isFile(),"Invalid experiment manifest");
        const spec=JSON.parse(fs.readFileSync(manifest,"utf8"));
        assert(new URL(spec.reference).protocol==="https:","Reference must use HTTPS");
        assert(typeof spec.candidate==="string"&&/^\/(?!\/)/.test(spec.candidate)&&!spec.candidate.includes("\\"),"Invalid candidate path");
        assert(Array.isArray(spec.scenarios)&&spec.scenarios.length,"Missing scenarios");
        const seen=new Set();
        for(const scenario of spec.scenarios) {
            assert(id.test(scenario.id)&&!seen.has(scenario.id),"Invalid or duplicate scenario");
            seen.add(scenario.id);
            assert(["width","height"].every(k=>Number.isInteger(scenario.viewport?.[k])&&scenario.viewport[k]>0),"Invalid viewport");
            assert(Array.isArray(scenario.elements)&&scenario.elements.length,"Missing elements");
            const elementIds=new Set(["viewport"]);
            for(const mapping of scenario.elements) {
                assert(id.test(mapping.id)&&!elementIds.has(mapping.id),"Invalid or duplicate element");
                elementIds.add(mapping.id);
                for(const key of ["reference","candidate"]) assert(typeof mapping[key]==="string"&&mapping[key].trim(),"Missing selector");
            }
            for(const action of scenario.actions||[]) {
                assert(["hover","click","focus","scroll"].includes(action.kind),"Invalid action");
                for(const key of ["reference","candidate"]) assert(typeof action[key]==="string"&&action[key].trim(),"Missing action selector");
            }
        }
        return {id:entry.name,directory,spec};
    });
    assert(experiments.length,"No experiments discovered");
    return experiments;
}
function compare(expected,actual,tolerance,ids) {
    assert.deepEqual(expected.viewport,actual.viewport,"Reference viewport differs");
    const differences=[];
    for(const id of ids) {
        const e=expected.elements[id],a=actual.elements[id];
        assert(e&&a,"Missing element "+id);
        for(const key of ["x","y","width","height"]) {
            assert(Number.isFinite(e.rect[key])&&Number.isFinite(a.rect[key]),"Invalid geometry");
            if(Math.abs(e.rect[key]-a.rect[key])>tolerance) differences.push(id+"."+key+": expected "+e.rect[key]+", actual "+a.rect[key]);
        }
        for(const key of Object.keys(a.style)) {
            assert(Object.hasOwn(e.style,key),"Missing reference style "+key);
            if(e.style[key]!==a.style[key]) differences.push(id+"."+key+": expected "+e.style[key]+", actual "+a.style[key]);
        }
        assert(Object.keys(e.style).length===Object.keys(a.style).length,"Unexpected reference styles");
        if(e.text!==a.text) differences.push(id+": text differs");
        for(const key of Object.keys(a.state)) {
            assert(Object.hasOwn(e.state,key),"Missing reference state "+key);
            if(e.state[key]!==a.state[key]) differences.push(id+"."+key+": expected "+e.state[key]+", actual "+a.state[key]);
        }
    }
    return differences;
}
module.exports={discover,compare};
