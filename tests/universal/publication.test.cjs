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
const delivery = path.join(root, "dependencies/managed/packages/ci-engine/src/adapters/github/delivery.cjs");
const { normalize } = require(delivery);

test("real publication component reconciles synthetic labels only in an authorized same-run Publish phase", async t => {
	const repository = "rehearsal/fixture";
	const sha = "a".repeat(40);
	const safe = Object.fromEntries(Object.entries(process.env).filter(([key]) => /^(PATH|PATHEXT|SYSTEMROOT|WINDIR|TEMP|TMP|TMPDIR|HOME|USERPROFILE)$/i.test(key)));
	const env = { ...safe, GITHUB_ACTIONS: "true", GITHUB_REPOSITORY: repository,
		GITHUB_EVENT_NAME: "repository_dispatch", GITHUB_REF: "refs/heads/source", GITHUB_SHA: sha,
		CI_ORIGIN_TRUSTED: "true", CI_ORIGIN_EVENT: "workflow_dispatch", CI_DEFAULT_BRANCH: "source", CI_ORIGIN_REF: "refs/heads/source", CI_SOURCE_SHA: sha,
		CI_EVENT: "push", CI_PHASE: "publish", CI_GRAPH_RUN: "true", CI_PUBLICATION_ENABLED: "true",
		GH_TOKEN: "rehearsal-token", TEMPLATE_PUBLICATION_REHEARSAL: "1" };
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
		await assert.rejects(run(invoke, {CI_GRAPH_RUN:"false", GITHUB_REF:"refs/heads/source"}), /confirmed same-run trusted default-branch delivery/);
		await assert.rejects(run(invoke, {CI_PHASE:"build"}), /confirmed same-run trusted default-branch delivery/);
		assert.deepEqual(mock.operations, []);
		const runId="publication-rehearsal-"+process.pid;
		t.after(()=>fs.rmSync(path.join(root,"build/run",runId),{recursive:true,force:true}));
		const entry=normalize({jobs:[{id:"work/labels/sync",lane:"issues",environment:"ci-publication",
			command:[lute,"run",path.join(root,"dependencies/managed/packages/ci-engine/src/native/entry.luau"),"--component","work/labels/sync"]}]}).jobs[0];
		const deliveryEnv={...env,CI_ORIGIN_SHA:sha,CI_DELIVERY_OPERATION:"publish",CI_DELIVERY_CONFIRM:"true",
			CI_DELIVERY_LANE:"issues",CI_DELIVERY_ENTRY:JSON.stringify(entry),CI_RUN_ID:runId};
		const deliver=extra=>exec(process.execPath,[delivery,"delivery-run"],{cwd:root,env:{...deliveryEnv,...extra},timeout:30000});
		await assert.rejects(deliver({CI_DELIVERY_LANE:"contents"}),/permission lane mismatch/);
		await assert.rejects(deliver({CI_ORIGIN_TRUSTED:"false"}),/trusted default-branch admission/);
		assert.deepEqual(mock.operations,[]);
		await deliver({});
		mock.assertLabels();
		assert.deepEqual(mock.violations, []);
		assert.equal(mock.operations.filter(x => x === "create label").length, 1);
	} finally {
		await new Promise(resolve => mock.server.close(resolve));
	}
});
