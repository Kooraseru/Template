import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test, { type TestContext } from "node:test";
import { main } from "./index.ts";
import { withStage } from "./publication.ts";

function workspace(t: TestContext) {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "dependency-providers-"));
	t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	const write = (file: string, content: string) => {
		const full = path.join(root, file);
		fs.mkdirSync(path.dirname(full), { recursive: true });
		fs.writeFileSync(full, content);
	};
	const read = (file: string) => fs.readFileSync(path.join(root, file), "utf8");
	const installed = "dependencies/managed/bin/example/tool.cjs";
	const lock = "dependencies/dependencies.lock";
	const adapter = ["node", "dependencies/providers/fixture.cjs"];
	write(adapter[1], fs.readFileSync(new URL("./tests/provider.cjs", import.meta.url), "utf8"));
	write("dependencies/packages/fixture/version", "first");
	const manifest = {
		providers: { local: { builtin: "local" }, seed: { command: adapter }, custom: { command: adapter } },
		dependencies: {
			"tool.example": { provider: "custom", needs: ["tool.seed"], options: { kind: "tool", target: "bin/example" } },
			"tool.seed": { provider: "seed", needs: ["local.fixture"], options: { kind: "seed", target: "share/seed", revision: "first" } },
			"local.fixture": { provider: "local", options: { path: "packages/fixture" } },
		},
	};
	const save = () => write("dependencies/dependencies.json", JSON.stringify(manifest));
	save();
	return { root, write, read, installed, lock, manifest, save };
}

test("standalone providers resolve and install against exports from other providers", async t => {
	const { root, lock, installed, read } = workspace(t);
	await main(["--update-lock"], root);
	assert.equal(fs.existsSync(path.join(root, installed)), false);
	assert.equal(JSON.parse(read(lock)).entries["tool.example"].resolution.value, "first");
	await main([], root);
	const stamp = fs.statSync(path.join(root, installed)).mtimeMs;
	await main([], root);
	assert.equal(fs.statSync(path.join(root, installed)).mtimeMs, stamp);
	const script = "const { main } = await import(process.argv[1]); process.exitCode = await main(['--exec','tool.example','forwarded'], process.argv[2]);";
	const result = spawnSync(process.execPath, ["--input-type=module", "-e", script, new URL("./index.ts", import.meta.url).href, root], { encoding: "utf8" });
	assert.equal(result.status, 0, result.stderr);
	assert.equal(result.stdout.trim(), "first forwarded");
});

test("stale locks, failed resolves, and failed installs preserve the last usable state", async t => {
	const { root, write, lock, read, installed, manifest, save } = workspace(t);
	await main(["--update-lock"], root);
	await main([], root);
	const originalLock = read(lock);
	const originalInstall = read(installed);
	manifest.dependencies["tool.seed"].options.revision = "second";
	save();
	await assert.rejects(main([], root), /stale lock entry for tool.seed/);
	write("dependencies/packages/fixture/version", "second");
	write("fail-resolve-tool", "");
	await assert.rejects(main(["--update-lock"], root), /tool.example resolve failed/);
	assert.equal(read(lock), originalLock);
	assert.equal(read(installed), originalInstall);
	fs.unlinkSync(path.join(root, "fail-resolve-tool"));
	await main(["--update-lock"], root);
	write("fail-install-tool", "");
	await assert.rejects(main([], root), /tool.example install failed/);
	assert.equal(read(installed), originalInstall);
	assert.equal(read("dependencies/managed/share/seed/value"), "first");
	fs.unlinkSync(path.join(root, "fail-install-tool"));
	await main([], root);
	assert.match(read(installed), /second/);
});

test("missing prerequisites, cycles, and output conflicts fail clearly", async t => {
	const { root, manifest, save } = workspace(t);
	manifest.dependencies["tool.example"].needs = ["missing"];
	save();
	await assert.rejects(main(["--update-lock"], root), /Missing prerequisite missing/);
	manifest.dependencies["tool.example"].needs = ["tool.seed"];
	manifest.dependencies["tool.seed"].needs = ["tool.example"];
	save();
	await assert.rejects(main(["--update-lock"], root), /Dependency cycle/);
	manifest.dependencies["tool.seed"].needs = ["local.fixture"];
	manifest.dependencies["tool.example"].options.target = "share/seed/nested";
	save();
	await main(["--update-lock"], root);
	await assert.rejects(main([], root), /Conflicting output/);
	assert.equal(fs.existsSync(path.join(root, "dependencies/managed/share/seed")), false);
});

test("setup recovers an interrupted publication before starting the next one", async t => {
	const { root, write, read } = workspace(t);
	const stage = ".loader-stage-interrupted";
	write("dependencies/managed/bin/tool/value", "interrupted");
	write("dependencies/managed/" + stage + "/.backup/0/value", "previous");
	write("dependencies/managed/.loader-journal.json", JSON.stringify({
		stage, changes: [{ to: "bin/tool", source: "source", existed: true }],
	}));
	const build = path.join(root, "dependencies/managed");
	await withStage(build, async () => {
		assert.equal(read("dependencies/managed/bin/tool/value"), "previous");
		assert.equal(fs.existsSync(path.join(build, ".loader-journal.json")), false);
	});
});

test("legacy provider export roots resolve to managed installations", async t => {
	const fixture = workspace(t);
	const provider = "dependencies/providers/fixture.cjs";
	fixture.write(provider, fixture.read(provider).replaceAll('root: "managed"', 'root: "build"'));
	await main(["--update-lock"], fixture.root);
	await main([], fixture.root);
	assert.ok(fs.existsSync(path.join(fixture.root, fixture.installed)));
	const state = JSON.parse(fixture.read("dependencies/managed/.loader-state.json"));
	assert.equal(state.entries["tool.example"].exports.cli.root, "managed");
});

test("setup regenerates act discovery options from the canonical config", async t => {
	const fixture = workspace(t);
	fixture.write(".vscode/config/act/actrc", "--detect-event\n--pull=false\n");
	await main(["--update-lock"], fixture.root);
	await main([], fixture.root);
	assert.equal(fixture.read(".actrc"), "--detect-event\n--pull=false\n");
	fixture.write(".vscode/config/act/actrc", "--detect-event\n--pull=true\n");
	await main([], fixture.root);
	assert.equal(fixture.read(".actrc"), "--detect-event\n--pull=true\n");
});
