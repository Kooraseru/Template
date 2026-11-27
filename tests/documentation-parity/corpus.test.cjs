"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),path=require("node:path"),fs=require("node:fs"),os=require("node:os");
const {loadCorpus,catalogue,coverage,compareCatalogue}=require("../../rules/documentation/parity/corpus.cjs");
const {loadReference,compareStructure}=require("../../rules/documentation/parity/structure.cjs");
const {discover}=require("../../rules/documentation/parity/comparison.cjs");
const rule=path.resolve(__dirname,"../../rules/documentation/parity");
const root=path.resolve(__dirname,"../..");
const sources=require("../../.vscode/config/rules.json").rules["documentation/parity"].settings.sources;
test("all independently acquired references have valid normalized trees",()=>{
    const documents=loadCorpus(root,sources);
    assert.equal(documents.length,10);
    assert.equal(documents.reduce((n,d)=>n+d.metadata.elements,0),41746);
    assert.equal(new Set(documents.map(d=>d.metadata.assetRevision)).size,1);
    const base=documents.find(d=>d.id==="base-part");
    const original=loadReference(path.join(rule,"references/base-part"));
    assert.equal(compareStructure(original,base.tree).differences.length,0);
});
test("cross-document catalogue retains counts and actual descendant variants",()=>{
    const documents=loadCorpus(root,sources);
    const components=catalogue(documents);
    const signature=components.find(x=>x.tag==="div"&&x.classes.includes("Typography-body1-Typography-root-signatureContainer"));
    assert(signature);
    assert.equal(signature.documents["base-part"],70);
    assert.equal(signature.documents["tween-service"],3);
    assert.equal(signature.documents["user-input-service"],66);
    assert.equal(signature.documents["vector3"],24);
    assert.equal(signature.documents["vector-library"],16);
    assert(signature.shapes.some(s=>Object.keys(s.documents).length>1));
    assert(components.some(x=>x.tag==="table"&&Object.hasOwn(x.documents,"material")));
    assert(components.some(x=>x.classes.includes("Typography-code")&&Object.hasOwn(x.documents,"events")));
});
test("reference acquisition is not a candidate parity pass",()=>{
    const docs=loadCorpus(root,sources), states=coverage(docs,discover(path.join(rule,"experiments")));
    assert.equal(states.filter(x=>x.status==="direct-comparison").length,1);
    assert.equal(states.filter(x=>x.status==="component-reference").length,9);
});
test("missing or corrupt corpus data fails closed",t=>{
    const folder=fs.mkdtempSync(path.join(os.tmpdir(),"parity-corpus-"));
    t.after(()=>fs.rmSync(folder,{recursive:true,force:true}));
    fs.mkdirSync(path.join(folder,"rules/documentation/parity"),{recursive:true});
    fs.cpSync(path.join(rule,"references"),path.join(folder,"rules/documentation/parity/references"),{recursive:true});
    const file=path.join(folder,"rules/documentation/parity/references/material/structure.json.gz.b64");
    fs.unlinkSync(file);
    assert.throws(()=>loadCorpus(folder,sources),/ENOENT/);
});

test("source registry is authoritative and rejects duplicates or invalid paths",()=>{
    assert.throws(()=>loadCorpus(root,[sources[0],sources[0]]),/duplicate reference ID/);
    assert.throws(()=>loadCorpus(root,[{...sources[0],reference:"../outside"}]),/Invalid reference path/);
    assert.throws(()=>loadCorpus(root,[{...sources[0],url:"https://example.invalid/"}]),/Configured URL differs/);
});
test("component catalogue distinguishes an untested reference from a mismatched candidate",()=>{
    const docs=loadCorpus(root,sources);
    const results=compareCatalogue(docs,[docs[0]]);
    assert(results.some(x=>x.status==="matching"));
    assert(results.some(x=>x.status==="untested"));
    assert(!results.some(x=>x.status==="different"||x.status==="unexpected"));
});
