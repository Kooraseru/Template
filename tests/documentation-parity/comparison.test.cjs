"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {compare,discover,compareScreenshots,screenshotManifest}=require("../../dependencies/managed/packages/documentation/parity/comparison.cjs");
const directory=path.resolve(__dirname,"../../rules/documentation/parity/tests");
for(const category of ["valid","invalid","review"]) for(const file of fs.readdirSync(path.join(directory,category))) {
    test(category+"/"+file,()=>{
        const fixture=JSON.parse(fs.readFileSync(path.join(directory,category,file),"utf8"));
        const check=()=>compare(fixture.expected,fixture.actual,1,["title"]);
        if(category==="review") assert.throws(check);
        else assert.equal(check().length>0,category==="invalid");
    });
}
test("discovers the declared BasePart scenarios with independent reference selectors",()=>{
    const experiment=discover(path.resolve(directory,"../experiments")).find(x=>x.id==="base-part");
    assert.ok(experiment);
    assert.deepEqual(experiment.spec.scenarios.map(x=>x.id),["desktop","mobile","anchored","method-signature"]);
    for(const scenario of experiment.spec.scenarios) for(const element of scenario.elements) {
        assert.notEqual(element.reference,element.candidate);
    }
});

test("committed screenshot digests detect changes without original image files",t=>{
    const os=require("node:os"), root=fs.mkdtempSync(path.join(os.tmpdir(),"parity-digest-"));
    t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
    const reference=path.join(root,"reference"), actual=path.join(root,"actual");
    fs.mkdirSync(reference);fs.mkdirSync(actual);
    fs.writeFileSync(path.join(reference,"viewport.png"),"original bytes");
    const manifest=screenshotManifest(reference,["viewport"]);
    fs.writeFileSync(path.join(reference,"screenshots.json"),JSON.stringify(manifest));
    fs.writeFileSync(path.join(actual,"viewport.png"),"original bytes");
    fs.unlinkSync(path.join(reference,"viewport.png"));
    assert.deepEqual(compareScreenshots(reference,actual,["viewport"]),[]);
    fs.writeFileSync(path.join(actual,"viewport.png"),"changed bytes");
    assert.deepEqual(compareScreenshots(reference,actual,["viewport"]),["viewport: screenshot differs"]);
    assert.throws(()=>compareScreenshots(reference,actual,["viewport","title"]),/Missing or unexpected/);
    fs.writeFileSync(path.join(reference,"viewport.png"),"tampered original");
    assert.throws(()=>compareScreenshots(reference,actual,["viewport"]),/does not match recorded digest/);
});
test("all BasePart scenarios have committed measured references",()=>{
    const experiment=discover(path.resolve(directory,"../experiments")).find(x=>x.id==="base-part");
    for(const scenario of experiment.spec.scenarios) {
        const root=path.join(experiment.directory,"reference",scenario.id);
        const expected=JSON.parse(fs.readFileSync(path.join(root,"metrics.json"),"utf8"));
        assert.deepEqual(expected.viewport,scenario.viewport);
        assert.deepEqual(compare(expected,expected,0,scenario.elements.map(x=>x.id)),[]);
        const manifest=JSON.parse(fs.readFileSync(path.join(root,"screenshots.json"),"utf8"));
        assert.deepEqual(Object.keys(manifest).sort(),["viewport",...scenario.elements.map(x=>x.id)].map(x=>x+".png").sort());
        for(const value of Object.values(manifest)) assert.match(value,/^[a-f0-9]{64}$/);
    }
});
