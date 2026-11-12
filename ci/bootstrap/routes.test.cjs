"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { readConfig, resolve, appendOutputs, runReadonly } = require("./routes.cjs");
const config = readConfig();
const trusted = { GITHUB_EVENT_NAME: "push", GITHUB_REF: "refs/heads/source" };

test("all CI events and declared operations route through one manifest", () => {
	assert.equal(resolve(config, trusted).name, "publish");
	assert.equal(resolve(config, { GITHUB_EVENT_NAME: "pull_request", GITHUB_REF: "refs/pull/12/merge" }).name, "review");
	assert.equal(resolve(config, { GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: "refs/heads/source" }).name, "validation");
	assert.equal(resolve(config, { GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: "refs/heads/source",
		CI_REQUESTED_OPERATION: "build" }).mode, "generated");
	assert.equal(resolve(config, { GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: "refs/heads/source",
		CI_REQUESTED_OPERATION: "publish", CI_REQUESTED_PUBLISH: "true" }).publication, true);
});
test("publication requires a trusted source ref and explicit manual approval", () => {
	for (const env of [
		{ ...trusted, GITHUB_REF: "refs/heads/topic" },
		{ GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: "refs/heads/source", CI_REQUESTED_OPERATION: "publish" },
		{ GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: "refs/heads/topic", CI_REQUESTED_OPERATION: "publish", CI_REQUESTED_PUBLISH: "true" },
	]) assert.throws(() => resolve(config, env));
	assert.equal(resolve(config, { GITHUB_EVENT_NAME: "pull_request", CI_REQUESTED_OPERATION: "publish" }).name, "review");
});
test("bootstrap outputs use aliases rather than credential values", () => {
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ci-routes-"));
	try {
		const file = path.join(directory, "outputs");
		appendOutputs(resolve(config, trusted), file);
		const output = fs.readFileSync(file, "utf8");
		assert.match(output, /^app_private_key_name=CI_APP_PRIVATE_KEY$/m);
		assert.match(output, /^branch_prefix=ci\/run-$/m);
		assert.doesNotMatch(output, /ghp_|github_pat_/);
	} finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
test("new operations do not require a change to authored YAML", () => {
	const copy = structuredClone(config);
	copy.operations["format-check"] = { mode: "readonly", events: ["workflow_dispatch"], checks: ["workflows"] };
	assert.equal(resolve(copy, { GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: "refs/heads/source",
		CI_REQUESTED_OPERATION: "format-check" }).name, "format-check");
	const workflow = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/ci.yml"), "utf8");
	assert.doesNotMatch(workflow, /publish-(general|projects|rulesets):/);
});
test("read-only route parsing does not require managed credential packages", () => {
	const readonly = readConfig(undefined, { requireCredentials: false });
	assert.equal(resolve(readonly, { GITHUB_EVENT_NAME: "pull_request" }).name, "review");
	assert.equal(readonly.bootstrap.environment, "ci-bootstrap");
	assert.equal(readonly.bootstrap.appIdVariable, undefined);
});

test("read-only executor will not run a generated operation", () => {
	assert.throws(() => runReadonly(config, resolve(config, trusted)), /Only unprivileged/);
});
