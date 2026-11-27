"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),path=require("node:path"),fs=require("node:fs"),os=require("node:os");
const {loadCorpus,catalogue,coverage}=require("../../rules/documentation/parity/corpus.cjs");
const {loadReference,compareStructure}=require("../../rules/documentation/parity/structure.cjs");
const {discover}=require("../../rules/documentation/parity/comparison.cjs");
const rule=path.resolve(__dirname,"../../rules/documentation/parity");
const corpus=path.join(rule,"corpus");
test("all independently acquired references have valid normalized trees",()=>{
    const documents=loadCorpus(corpus);
    assert.equal(documents.length,10);
    assert.equal(documents.reduce((n,d)=>n+d.metadata.elements,0),41746);
    assert.equal(new Set(documents.map(d=>d.metadata.assetRevision)).size,1);
    const base=documents.find(d=>d.id==="base-part");
    const original=loadReference(path.join(rule,"experiments/base-part/reference"));
    assert.equal(compareStructure(original,base.tree).differences.length,0);
});
test("cross-document catalogue retains counts and actual descendant variants",()=>{
    const documents=loadCorpus(corpus);
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
    const docs=loadCorpus(corpus), states=coverage(docs,discover(path.join(rule,"experiments")));
    assert.equal(states.filter(x=>x.status==="configured").length,1);
    assert.equal(states.filter(x=>x.status==="reference-only").length,9);
});
test("missing or corrupt corpus data fails closed",t=>{
    const folder=fs.mkdtempSync(path.join(os.tmpdir(),"parity-corpus-"));
    t.after(()=>fs.rmSync(folder,{recursive:true,force:true}));
    fs.cpSync(corpus,folder,{recursive:true});
    const file=path.join(folder,"references/material/structure.json.gz.b64");
    fs.unlinkSync(file);
    assert.throws(()=>loadCorpus(folder),/ENOENT/);
});
