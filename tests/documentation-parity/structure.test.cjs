"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),path=require("node:path");
const {count,compareStructure,loadReference}=require("../../rules/documentation/parity/structure.cjs");
const tree=(children,labels=[["main",[]],["span",["title"]],["button",["copy"]],["div",["wrapper"]]])=>({labels,nodes:[[1],[2],[3,0],[0,...children]],root:3});
test("full independently captured article can be decoded and compared",()=>{
    const reference=loadReference(path.resolve(__dirname,"../../rules/documentation/parity/experiments/base-part/reference"));
    assert.equal(count(reference),13877);
    const result=compareStructure(reference,reference);
    assert.equal(result.matched,13877);assert.equal(result.differences.length,0);
});
test("missing, unexpected, and reordered children are distinct structural violations",()=>{
    const expected=tree([0,1]);
    assert.equal(compareStructure(expected,tree([1,0])).counts.order,1);
    assert.equal(compareStructure(expected,tree([0])).counts.missing,1);
    assert.equal(compareStructure(expected,tree([0,1,0])).counts.unexpected,1);
    const wrapped=compareStructure(expected,tree([2,1]));
    assert.equal(wrapped.counts.missing,1);assert.equal(wrapped.counts.unexpected,2);
    assert(wrapped.differences.some(x=>x.path.includes("wrapper")));
});
test("class rename and tag changes cannot pass",()=>{
    const expected=tree([0,1]);
    const changed=tree([0,1],[["main",[]],["h1",["heading"]],["button",["copy"]],["div",["wrapper"]]]);
    assert.equal(compareStructure(expected,changed).counts.missing,1);
    assert.equal(compareStructure(expected,changed).counts.unexpected,1);
});
test("malformed or cyclic trees fail closed",()=>{
    assert.throws(()=>count({labels:[["main",[]]],nodes:[[0,0]],root:0}),/cyclic/);
});
