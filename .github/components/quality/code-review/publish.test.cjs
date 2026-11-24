"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { reviewBase } = require("./review.cjs");
const { commentsFor, submitReviews, reconcile, resolveThread } = require("./publish.cjs");

test("independent PR reviews scope findings to the admitted default branch", () => {
  assert.equal(reviewBase({ CI_ORIGIN_EVENT: "pull_request", CI_DEFAULT_BRANCH: "source" }), "source");
  assert.equal(reviewBase({ CI_ORIGIN_EVENT: "push", CI_DEFAULT_BRANCH: "source" }), null);
  assert.throws(() => reviewBase({ CI_ORIGIN_EVENT: "pull_request" }), /missing its default branch/);
});

test("review comments point only to added lines and deduplicate findings", () => {
  const file = "source/Example/init.luau";
  const files = [{ filename: file, patch: "@@ -2,3 +2,4 @@\n context\n-old\n+new\n+extra\n context" }];
  const finding = { file, line: 3, source: "luau/const-bindings", severity: "error", message: "Use const." };
  const comments = [...commentsFor([
    finding, finding, { ...finding, line: 2 }, { ...finding, line: 4, fixture: true },
    { ...finding, line: 4, infrastructure: true }, { ...finding, file: "other.luau" },
  ], files).values()];
  assert.equal(comments.length, 1);
  assert.deepEqual([comments[0].path, comments[0].line, comments[0].side], [file, 3, "RIGHT"]);
  assert.match(comments[0].body, /Use const/);
});

test("all review comments are sent in batches and stop if the head changes", () => {
  const comments = Array.from({ length: 123 }, (_, line) => ({ line }));
  const batches = [];
  submitReviews(comments, () => true, batch => batches.push(batch));
  assert.deepEqual(batches.map(batch => batch.length), [50, 50, 23]);
  assert.deepEqual(batches.flat(), comments);

  const stale = [];
  submitReviews(comments, () => stale.length === 0, batch => stale.push(batch));
  assert.deepEqual(stale, [comments.slice(0, 50)]);
});

test("review refresh reuses shifted findings and resolves only obsolete bot-only threads", () => {
  const file = "source/Example/init.luau";
  const files = [{ filename: file, patch: "@@ -1,1 +1,3 @@\n old\n+new\n+extra" }];
  const finding = { file, line: 2, source: "Rules", severity: "warning", message: "Current finding" };
  const desired = commentsFor([finding, {...finding, line:3,message:"New finding"}], files);
  const old = [...commentsFor([{...finding,line:3}], files).values()][0];
  const thread = (id, overrides = {}) => ({ id, path:file, line:2, diffSide:"RIGHT", isOutdated:false, isResolved:false,
    comments:{ totalCount:1, nodes:[{body:old.body,author:{login:"github-actions"}}]}, ...overrides });
  const existing = [
    thread("shifted"),
    thread("duplicate"),
    thread("outdated",{isOutdated:true,line:null}),
    thread("human",{comments:{totalCount:1,nodes:[{body:old.body,author:{login:"human"}}]}}),
    thread("discussion",{line:1,comments:{totalCount:2,nodes:[{body:old.body,author:{login:"github-actions"}}]}}),
    thread("already-resolved",{line:1,isResolved:true}),
    thread("omitted-patch",{path:"other.luau"}),
  ];
  const plan = reconcile(desired, existing, true, [...files,{filename:"other.luau"}]);
  assert.deepEqual(plan.resolve, ["duplicate","outdated"]);
  assert.equal(plan.comments.length,1);
  assert.match(plan.comments[0].body,/New finding/);
  assert.deepEqual(reconcile(desired, existing, false, files).resolve, []);
  assert.deepEqual(reconcile(new Map(), [thread("fixed")], true, files).resolve, ["fixed"]);
  assert.deepEqual(reconcile(new Map(), [thread("fixed")], false, files).resolve, []);
});
test("manually resolved current findings are not recreated on reruns", () => {
  const file = "example.luau", files = [{filename:file,patch:"@@ -0,0 +1 @@\n+value"}];
  const desired = commentsFor([{file,line:1,source:"Rules",severity:"warning",message:"A finding"}],files);
  const item = [...desired.values()][0];
  const thread = {id:"closed",path:file,line:1,diffSide:"RIGHT",isResolved:true,isOutdated:false,
    comments:{totalCount:1,nodes:[{body:item.body,author:{login:"github-actions[bot]"}}]}};
  assert.deepEqual(reconcile(desired,[thread],true,files),{comments:[],resolve:[]});
});

test("only GitHub's known thread resolution permission refusal is nonfatal", () => {
  assert.equal(resolveThread("test", () => ({})), true);
  assert.equal(resolveThread("test", () => { throw Object.assign(new Error("GraphQL failed"), { stderr: "Resource not accessible by integration" }); }), false);
  assert.throws(() => resolveThread("test", () => { throw new Error("HTTP 500"); }), /HTTP 500/);
});
