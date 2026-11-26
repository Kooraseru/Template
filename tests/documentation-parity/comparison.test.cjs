"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {compare,discover}=require("../../rules/documentation/parity/comparison.cjs");
const directory=path.resolve(__dirname,"../../rules/documentation/parity/tests");
for(const category of ["valid","invalid","review"]) for(const file of fs.readdirSync(path.join(directory,category))) {
    test(category+"/"+file,()=>{
        const fixture=JSON.parse(fs.readFileSync(path.join(directory,category,file),"utf8"));
        const check=()=>compare(fixture.expected,fixture.actual,1,["title"]);
        if(category==="review") assert.throws(check);
        else assert.equal(check().length>0,category==="invalid");
    });
}
test("discovers BasePart scenarios",()=>assert.ok(discover(path.resolve(directory,"../experiments")).some(x=>x.id==="base-part"&&x.spec.scenarios.length===2)));
