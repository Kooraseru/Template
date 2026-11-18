"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { parseRepositoryRemote, targetRepository, identity, analyze, present } = require("./readiness.cjs");

test("origin parser supports HTTPS and SSH without using a network connection", () => {
  assert.equal(parseRepositoryRemote("https://github.com/Example/Project.git"), "Example/Project");
  assert.equal(parseRepositoryRemote("git@github.com:Example/Project.git"), "Example/Project");
  assert.equal(parseRepositoryRemote("ssh://git@github.com/Example/Project.git"), "Example/Project");
  assert.equal(parseRepositoryRemote("https://example.com/not-github"), null);
});
test("repository target is scoped to [github] and may use current", () => {
  assert.equal(targetRepository('[github]\nrepository = "current"\n\n[github.aliases]\nexample = "foo/bar"\n'), "current");
  assert.equal(targetRepository('[github]\nrepository = "a/b"\n[github.bootstrap]\n'), "a/b");
});
test("event context handles custom default branch without hardcoded source", () => {
  const context = identity({ GITHUB_REPOSITORY: "Other/Repository", CI_DEFAULT_BRANCH: "development" }, __dirname);
  assert.deepEqual(context, { repository: "Other/Repository", defaultBranch: "development" });
});
test("new repository readiness requires no hosted credentials", () => {
  const report = analyze(undefined, { GITHUB_REPOSITORY: "Other/Repository", CI_DEFAULT_BRANCH: "development" });
  assert.equal(report.ready, true, present(report));
  assert.equal(report.configuredRepository, "current");
  assert.equal(report.defaultBranch, "development");
  assert.equal(report.generatedBranchConfigured, true);
  assert.equal(report.publicationEnabled, false);
});
