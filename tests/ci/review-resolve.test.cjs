"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { resolve } = require("../../.github/components/quality/code-review/resolve.cjs");
const repo = "Example/Project", sha = "a".repeat(40);
function fixture({ fork = false, closed = false, stale = false, wrongWorkflow = false, merged = false } = {}) {
  const head = { id: fork ? 2 : 1, full_name: fork ? "Other/Project" : repo };
  const pr = { number: 42, state: closed ? "closed" : "open", merged,
    merge_commit_sha: merged ? "b".repeat(40) : null,
    base: { repo: { id: 1 }, ref: "source" },
    head: { repo: head, ref: "feature/test", sha: stale ? "c".repeat(40) : sha } };
  const event = { action: "completed", repository: { id: 1, full_name: repo, default_branch: "source" },
    workflow_run: { id: 100, run_attempt: 1 } };
  const mode = closed ? "closed" : "open";
  const get = p => {
    if (p.includes("/actions/workflows/")) return { id: 10, path: ".github/workflows/" + (closed ? "close.yml" : "ci.yml") };
    if (p.endsWith("/actions/runs/100")) return { id: 100, run_attempt: 1, workflow_id: wrongWorkflow ? 99 : 10,
      event: "pull_request", status: "completed", conclusion: "success", repository: { id: 1 },
      head_repository: head, head_branch: merged ? "source" : "feature/test", head_sha: merged ? pr.merge_commit_sha : sha,
      pull_requests: fork || merged ? [] : [{ number: 42 }] };
    if (p.includes("/commits/")) return [pr];
    if (p.includes("/pulls?")) return [pr];
    if (p.endsWith("/pulls/42")) return pr;
    throw Error("Unexpected endpoint: " + p);
  };
  return () => resolve(event, mode, get, repo);
}
test("same-repo and fork intakes resolve the exact current head", () => {
  for (const fork of [false, true]) assert.deepEqual(fixture({ fork })(), { pr: "42", sha, ref: "refs/heads/feature/test" });
});
test("stale head is skipped and unrelated workflows fail closed", () => {
  assert.equal(fixture({ stale: true })(), null);
  assert.throws(fixture({ wrongWorkflow: true }), /Unexpected intake/);
});
test("closed same-repo PRs retire, including merge commits; forks do not", () => {
  assert.equal(fixture({ closed: true })().pr, "42");
  assert.equal(fixture({ closed: true, merged: true })().pr, "42");
  assert.equal(fixture({ closed: true, fork: true })(), null);
});
