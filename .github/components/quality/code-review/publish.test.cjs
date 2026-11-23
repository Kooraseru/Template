"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { reviewBase } = require("./review.cjs");
const { commentsFor, submitReviews } = require("./publish.cjs");

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
