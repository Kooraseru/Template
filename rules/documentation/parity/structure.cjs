"use strict";
const assert=require("node:assert/strict"), fs=require("node:fs"), path=require("node:path");
const {gunzipSync}=require("node:zlib"),{createHash}=require("node:crypto");

// This function is evaluated directly in the browser, with no closure dependencies.
// Keep the reference and candidate normalization identical.
function snapshot(root) {
    const labels=[],nodes=[],labelIds=new Map(),nodeIds=new Map();
    function walk(element) {
        const classes=[...element.classList]
            .filter(name=>!/^web-blox-css-mui-/.test(name)&&!/^web-blox-css-tss-[a-z0-9]+$/.test(name))
            .map(name=>name.replace(/^web-blox-css-tss-[a-z0-9]+-/,""));
        const label=[element.localName,[...new Set(classes)].sort()];
        const key=JSON.stringify(label);
        if(!labelIds.has(key)){labelIds.set(key,labels.length);labels.push(label);}
        const node=[labelIds.get(key),...[...element.children].filter(child=>!["script","style"].includes(child.localName)).map(walk)];
        const shape=JSON.stringify(node);
        if(!nodeIds.has(shape)){nodeIds.set(shape,nodes.length);nodes.push(node);}
        return nodeIds.get(shape);
    }
    const index=walk(root);
    return {labels,nodes,root:index};
}

function loadReference(directory) {
    const provenance=JSON.parse(fs.readFileSync(path.join(directory,"structure-provenance.json"),"utf8"));
    const raw=gunzipSync(Buffer.from(fs.readFileSync(path.join(directory,"structure.json.gz.b64"),"utf8").trim(),"base64"),{maxOutputLength:16*1024*1024});
    assert.equal(createHash("sha256").update(raw).digest("hex"),provenance.normalizedSha256,"Reference structure integrity mismatch");
    const tree=JSON.parse(raw);
    assert.equal(count(tree),provenance.elements,"Reference structure element count mismatch");
    return tree;
}
function count(tree) {
    assert(Array.isArray(tree.labels)&&Array.isArray(tree.nodes)&&Number.isInteger(tree.root),"Invalid structure");
    const sizes=[];
    for(const label of tree.labels) assert(Array.isArray(label)&&label.length===2&&typeof label[0]==="string"&&Array.isArray(label[1])&&label[1].every(x=>typeof x==="string"),"Invalid element label");
    for(const node of tree.nodes) {
        const i=sizes.length;
        assert(Array.isArray(node)&&node.length>0&&Number.isInteger(node[0])&&tree.labels[node[0]],"Invalid node label");
        assert(node.slice(1).every(child=>Number.isInteger(child)&&child>=0&&child<i),"Invalid or cyclic child");
        const size=1+node.slice(1).reduce((total,child)=>total+sizes[child],0);
        assert(size<=1000000,"Structure exceeds element limit");
        sizes.push(size);
    }
    assert(sizes[tree.root]>0,"Missing tree root");
    return sizes[tree.root];
}
function compareStructure(expected,actual) {
    const expectedCount=count(expected),actualCount=count(actual);
    const inventory=new Map(),differences=[],componentShapes=new Map();
    const label=(tree,index)=>tree.labels[tree.nodes[index][0]];
    const name=(tree,index)=>{const [tag,classes]=label(tree,index);return tag+(classes.length?"."+classes.join("."):"");};
    const key=(tree,index)=>JSON.stringify(label(tree,index));
    function collect(tree,index,side) {
        const id=key(tree,index);
        if(!inventory.has(id))inventory.set(id,{element:name(tree,index),expected:0,actual:0});
        inventory.get(id)[side]++;
        for(const child of tree.nodes[index].slice(1))collect(tree,child,side);
    }
    collect(expected,expected.root,"expected");collect(actual,actual.root,"actual");
    // A component may already match even if an ancestor has a different name.
    // Compare the full descendant tree independently of its absolute location,
    // without forgiving the strict path mismatch above it.
    function shapes(tree,side){
        const hashes=[];
        for(const node of tree.nodes){
            const identity=tree.labels[node[0]];
            const children=node.slice(1).map(child=>hashes[child]);
            hashes.push(createHash("sha256").update(JSON.stringify([identity,children])).digest("hex"));
        }
        function visit(index){
            const identity=label(tree,index);
            if(identity[1].length) {
                const id=key(tree,index);
                if(!componentShapes.has(id))componentShapes.set(id,{element:name(tree,index),expected:0,actual:0,expectedShapes:new Map(),actualShapes:new Map()});
                const entry=componentShapes.get(id),map=entry[side+"Shapes"],hash=hashes[index];
                entry[side]++;map.set(hash,(map.get(hash)||0)+1);
            }
            for(const child of tree.nodes[index].slice(1))visit(child);
        }
        visit(tree.root);
    }
    shapes(expected,"expected");shapes(actual,"actual");
    const components=[...componentShapes.values()].map(entry=>{
        const matchingSubtrees=[...entry.expectedShapes].reduce((total,[hash,n])=>total+Math.min(n,entry.actualShapes.get(hash)||0),0);
        return {element:entry.element,expected:entry.expected,actual:entry.actual,matchingSubtrees,
            missingShapes:[...entry.expectedShapes].filter(([hash,n])=>n>(entry.actualShapes.get(hash)||0)).map(([hash,n])=>({hash,count:n-(entry.actualShapes.get(hash)||0)})),
            unexpectedShapes:[...entry.actualShapes].filter(([hash,n])=>n>(entry.expectedShapes.get(hash)||0)).map(([hash,n])=>({hash,count:n-(entry.expectedShapes.get(hash)||0)}))};
    }).sort((a,b)=>a.element.localeCompare(b.element));
    const matchingNamedSubtrees=components.reduce((sum,entry)=>sum+entry.matchingSubtrees,0);
    function children(tree,index){
        const seen=new Map();
        return tree.nodes[index].slice(1).map(child=>{
            const id=key(tree,child),ordinal=(seen.get(id)||0)+1;seen.set(id,ordinal);
            return {index:child,id:JSON.stringify([id,ordinal]),name:name(tree,child)+"["+ordinal+"]"};
        });
    }
    function unmatched(tree,index,location,kind){
        differences.push({kind,path:location,element:name(tree,index)});
        for(const child of children(tree,index))unmatched(tree,child.index,location+"/"+child.name,kind);
    }
    let matched=0;
    function walk(e,a,location) {
        if(key(expected,e)===key(actual,a))matched++;
        else differences.push({kind:"identity",path:location,expected:name(expected,e),actual:name(actual,a)});
        const ec=children(expected,e),ac=children(actual,a),em=new Map(ec.map(x=>[x.id,x])),am=new Map(ac.map(x=>[x.id,x]));
        const expectedOrder=ec.filter(x=>am.has(x.id)).map(x=>x.id),actualOrder=ac.filter(x=>em.has(x.id)).map(x=>x.id);
        if(JSON.stringify(expectedOrder)!==JSON.stringify(actualOrder))differences.push({kind:"order",path:location,expected:ec.map(x=>x.name),actual:ac.map(x=>x.name)});
        for(const child of ec) {
            const other=am.get(child.id),next=location+"/"+child.name;
            if(other)walk(child.index,other.index,next);
            else unmatched(expected,child.index,next,"missing");
        }
        for(const child of ac)if(!em.has(child.id))unmatched(actual,child.index,location+"/"+child.name,"unexpected");
    }
    walk(expected.root,actual.root,"$");
    const counts=Object.fromEntries(["identity","missing","unexpected","order"].map(kind=>[kind,differences.filter(x=>x.kind===kind).length]));
    return {expectedCount,actualCount,matched,matchingNamedSubtrees,components,counts,inventory:[...inventory.values()].filter(x=>x.expected!==x.actual).sort((a,b)=>Math.abs(b.expected-b.actual)-Math.abs(a.expected-a.actual)),differences};
}
module.exports={snapshot,loadReference,count,compareStructure};
