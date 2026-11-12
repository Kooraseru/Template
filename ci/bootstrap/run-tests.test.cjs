"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { discover } = require("./run-tests.cjs");

test("Template and project-owned tests have independent discovery and ownership", t => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "ci-tests-"));
	t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	function add(file, content = "") {
		const target = path.join(root, file);
		fs.mkdirSync(path.dirname(target), { recursive: true });
		fs.writeFileSync(target, content);
	}
	add("ci/core.test.cjs");
	add("dependencies/packages/lib/lib.test.ts");
	add("tests/universal/invariant.test.cjs");
	add("tests/features/networking/network.test.cjs");
	add("tests/features/compiler/suite.json", JSON.stringify({ version: 1, command: ["node", "--test", "tests/features/compiler/compiler.test.cjs"], timeoutSeconds: 30 }));
	add("tests/features/compiler/compiler.test.cjs");
	const result = discover(root);
	assert.deepEqual(result.universal, ["ci/core.test.cjs", "dependencies/packages/lib/lib.test.ts", "tests/universal/invariant.test.cjs"]);
	assert.deepEqual(result.feature, ["tests/features/networking/network.test.cjs"]);
	assert.deepEqual(result.suites.map(s => s.directory), ["tests/features/compiler"]);
});
test("invalid or unbounded custom feature suites fail closed", t => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "ci-test-invalid-"));
	t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	fs.mkdirSync(path.join(root, "ci"), { recursive: true });
	fs.writeFileSync(path.join(root, "ci/root.test.cjs"), "");
	fs.mkdirSync(path.join(root, "tests/features/feature"), { recursive: true });
	fs.writeFileSync(path.join(root, "tests/features/feature/suite.json"),
		JSON.stringify({ version: 1, command: ["node", "a"], timeoutSeconds: 0 }));
	assert.throws(() => discover(root), /Invalid feature test suite/);
});
