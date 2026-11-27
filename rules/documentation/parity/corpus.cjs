"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {loadReference,count}=require("./structure.cjs");

function loadCorpus(directory){
    const manifest=JSON.parse(fs.readFileSync(path.join(directory,"manifest.json"),"utf8"));
    const entries=Object.entries(manifest);
    assert(entries.length>0,"Empty reference corpus");
    const references=path.join(directory,"references");
    const ids=fs.readdirSync(references,{withFileTypes:true});
    assert(ids.every(x=>x.isDirectory()),"Unexpected corpus entry");
    assert.deepEqual(ids.map(x=>x.name).sort(),entries.map(([id])=>id).sort(),"Missing or unexpected reference directory");
    return entries.map(([id,metadata])=>{
        assert(/^[a-z][a-z0-9-]*$/.test(id),"Invalid reference ID");
        assert(new URL(metadata.url).protocol==="https:","Reference must use HTTPS");
        const folder=path.join(references,id);
        const provenance=JSON.parse(fs.readFileSync(path.join(folder,"structure-provenance.json"),"utf8"));
        assert.equal(provenance.normalizedSha256,metadata.normalizedSha256,"Reference manifest digest differs");
        assert.equal(provenance.sourceSha256,metadata.sourceSha256,"Source manifest digest differs");
        assert.equal(provenance.root,metadata.root,"Reference root differs");
        assert.equal(provenance.capture.url,metadata.url,"Reference URL differs");
        assert.equal(provenance.assetRevision,metadata.assetRevision,"Asset revision differs");
        const tree=loadReference(folder);
        assert.equal(count(tree),metadata.elements,"Reference element count differs");
        assert.equal(tree.labels.length,metadata.uniqueLabels,"Reference label count differs");
        assert.equal(tree.nodes.length,metadata.uniqueShapes,"Reference shape count differs");
        return {id,metadata,tree};
    });
}

// Index exact ordered descendant shapes across independently sourced documents.
// Occurrence counts are per document, never a sum a single candidate must match.
function catalogue(documents){
    const entries=new Map();
    for(const {id,tree} of documents){
        const hashes=[],sizes=[];
        for(const node of tree.nodes){
            hashes.push(createHash("sha256").update(JSON.stringify([tree.labels[node[0]],node.slice(1).map(child=>hashes[child])])).digest("hex"));
            sizes.push(1+node.slice(1).reduce((n,child)=>n+sizes[child],0));
        }
        function visit(index){
            const node=tree.nodes[index],label=tree.labels[node[0]];
            if(label[1].length){
                const key=JSON.stringify(label);
                if(!entries.has(key))entries.set(key,{tag:label[0],classes:label[1],documents:{},shapes:new Map()});
                const entry=entries.get(key);
                entry.documents[id]=(entry.documents[id]||0)+1;
                const hash=hashes[index];
                if(!entry.shapes.has(hash))entry.shapes.set(hash,{hash,elements:sizes[index],documents:{}});
                const shape=entry.shapes.get(hash);
                shape.documents[id]=(shape.documents[id]||0)+1;
            }
            for(const child of node.slice(1))visit(child);
        }
        visit(tree.root);
    }
    return [...entries.values()].map(entry=>({...entry,shapes:[...entry.shapes.values()].sort((a,b)=>a.hash.localeCompare(b.hash))})).sort((a,b)=>JSON.stringify([a.tag,a.classes]).localeCompare(JSON.stringify([b.tag,b.classes])));
}
function coverage(documents,experiments){
    return documents.map(({id,metadata})=>{
        const experiment=experiments.find(x=>x.id===id);
        if(experiment)assert.equal(experiment.spec.reference,metadata.url,"Experiment reference URL differs from corpus");
        return {id,url:metadata.url,elements:metadata.elements,assetRevision:metadata.assetRevision,status:experiment?"configured":"reference-only"};
    });
}
module.exports={loadCorpus,catalogue,coverage};
