"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {hosts,matrix}=require("./hosts.cjs");
test("host matrix derives every test from the real host contracts",()=>{
  const entries=matrix();
  assert.deepEqual(entries.map(x=>x.id),hosts());
  assert.deepEqual(entries.map(x=>x.id),["windows-amd","windows-arm64","windows-intel"]);
  assert.equal(entries.find(x=>x.id==="windows-arm64").runner,"windows-11-arm");
  for(const entry of entries){
    assert.equal(entry.file,entry.id+".exe");
    assert.equal(entry.expected[0],"Hello from the shared C application!");
    assert.equal(entry.expected.length,2);
  }
});
