import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { migrateLayout } from "./migration.ts";

test("layout migration preserves installed files and session state, is idempotent, and survives build deletion", async t => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "layout-migration-"));
	t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	const write = (file: string, value: string) => { fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true }); fs.writeFileSync(path.join(root, file), value); };
	write("build/dependencies/npm/installed.txt", "installed");
	write("build/dependencies/.loader-state.json", '{"entries":{}}');
	write("build/run/editor-problems/session-file.txt", "private session selection");
	await migrateLayout(root);
	assert.equal(fs.readFileSync(path.join(root, "dependencies/managed/npm/installed.txt"), "utf8"), "installed");
	assert.ok(fs.existsSync(path.join(root, "build/dependencies/npm/installed.txt")));
	write(".workspace/editor-problems/session-file.txt", "new selection");
	await migrateLayout(root);
	assert.equal(fs.readFileSync(path.join(root, ".workspace/editor-problems/session-file.txt"), "utf8"), "new selection");
	fs.rmSync(path.join(root, "build"), { recursive: true });
	assert.ok(fs.existsSync(path.join(root, "dependencies/managed/.loader-state.json")));
	assert.ok(fs.existsSync(path.join(root, ".workspace/editor-problems/session-file.txt")));
});
