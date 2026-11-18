"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { startMock } = require("../../dependencies/packages/checks/preflightChecker/bootstrap/githubMock.cjs");
const root = path.resolve(__dirname, "../..");
const lute = path.join(root, "dependencies/managed/bin/lute", process.platform === "win32" ? "lute.exe" : "lute");
const exec = promisify(execFile);

test("real publication component reconciles synthetic labels only on a generated Publish branch", async t => {
	const repository = "rehearsal/fixture";
	const route = JSON.parse(fs.readFileSync(path.join(root, "config/ci/operations.json"), "utf8")).operations.publish;
	const branch = route.branchPrefix + "1-1";
	const safe = Object.fromEntries(Object.entries(process.env).filter(([key]) => /^(PATH|PATHEXT|SYSTEMROOT|WINDIR|TEMP|TMP|TMPDIR|HOME|USERPROFILE)$/i.test(key)));
	const env = { ...safe, GITHUB_ACTIONS: "true", GITHUB_REPOSITORY: repository,
		GITHUB_EVENT_NAME: "push", GITHUB_REF: "refs/heads/" + branch,
		CI_EVENT: "push", CI_PHASE: "publish", CI_GRAPH_RUN: "true", CI_RUN_BRANCH: branch,
		CI_EXECUTION_PREFIX: route.branchPrefix, GH_TOKEN: "rehearsal-token", TEMPLATE_PUBLICATION_REHEARSAL: "1" };
	fs.mkdirSync(path.join(root, "build"), { recursive: true });
	const dir = fs.mkdtempSync(path.join(root, "build/publish-rehearsal-"));
	t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
	const labelFile = path.join(dir, "labels.luau");
	fs.writeFileSync(labelFile, 'local L=require("@components/work/labels/sync/labelCatalog")\nlocal J=require("@formats/json")\nprint(J.encode(L.Read()))');
	const invoke = path.join(dir, "publish.luau");
	fs.writeFileSync(invoke, 'local C=require("@components/work/labels/sync")\nC.new():Run({event="push"})');
	const run = (file, extra = {}) => exec(lute, ["run", file], { cwd: root, env: {...env, ...extra}, timeout: 30000 });
	const { stdout } = await run(labelFile);
	const labels = JSON.parse(stdout);
	assert.ok(labels.length > 0);
	const mock = await startMock({repository, labels}, "create");
	try {
		await assert.rejects(run(invoke, {CI_GRAPH_RUN:"false", GITHUB_REF:"refs/heads/source"}), /validated generated Publish run branch/);
		await assert.rejects(run(invoke, {CI_PHASE:"build"}), /validated generated Publish run branch/);
		assert.deepEqual(mock.operations, []);
		await run(invoke);
		mock.assertLabels();
		assert.deepEqual(mock.violations, []);
		assert.equal(mock.operations.filter(x => x === "create label").length, 1);
	} finally {
		await new Promise(resolve => mock.server.close(resolve));
	}
});
