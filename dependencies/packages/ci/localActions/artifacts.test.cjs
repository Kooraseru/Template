"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path"), os = require("node:os");
const { zipSync } = require("../../core/dependencyLoader/vendor/fflate.cjs");
const { unzip, tar, exportOutputs, promote, hash } = require("./artifacts.cjs");
function fixture(t) { const root = fs.mkdtempSync(path.join(os.tmpdir(), "ci-outputs-")); t.after(() => fs.rmSync(root, { recursive: true, force: true })); return root; }
function archive(entries) {
	const blocks = [];
	for (const [name, value, type = "0"] of entries) {
		const bytes = Buffer.from(value), header = Buffer.alloc(512); header.write(name); header.write("0000644\0", 100); header.write(bytes.length.toString(8).padStart(11, "0") + "\0", 124); header.write("        ", 148); header[156] = type.charCodeAt(0); header.write("ustar\0", 257); const sum = header.reduce((a, b) => a + b, 0); header.write(sum.toString(8).padStart(6, "0") + "\0 ", 148); blocks.push(header, bytes, Buffer.alloc((512 - bytes.length % 512) % 512));
	}
	return Buffer.concat([...blocks, Buffer.alloc(1024)]);
}
function bundle(root, runId, files) {
	const runRoot = path.join(root, "build/run", runId), directory = path.join(runRoot, "transport/1/outputs-example"); fs.mkdirSync(directory, { recursive: true });
	const entries = Object.entries(files), manifest = { version: 1, runId, source: "a".repeat(40), operation: "build", phase: "build", component: "example", complete: true, outcome: "passed", files: entries.map(([name, bytes]) => ({ path: name, size: Buffer.byteLength(bytes), sha256: hash(Buffer.from(bytes)) })) };
	fs.writeFileSync(path.join(directory, "outputs-example.zip"), zipSync({ "manifest.json": Buffer.from(JSON.stringify(manifest)), "outputs.tar": archive(entries) }));
	const expected = { runId, source: manifest.source, operation: "build", components: ["example"], tasks: [{ identity: "example", outputs: ["build/artifacts/**"] }] };
	return { runRoot, expected };
}
test("exports readable files, replaces owned output and removes stale files while preserving unrelated data", t => {
	const root = fixture(t), first = bundle(root, "first", { "build/artifacts/app.exe": "one", "build/artifacts/old.exe": "old" });
	const manifest = exportOutputs(first.runRoot, first.expected); promote(root, first.runRoot, manifest);
	assert.equal(fs.readFileSync(path.join(root, "build/artifacts/app.exe"), "utf8"), "one");
	fs.writeFileSync(path.join(root, "build/artifacts/user.txt"), "mine");
	const next = bundle(root, "next", { "build/artifacts/app.exe": "two" }); promote(root, next.runRoot, exportOutputs(next.runRoot, next.expected));
	assert.equal(fs.readFileSync(path.join(root, "build/artifacts/app.exe"), "utf8"), "two"); assert.ok(!fs.existsSync(path.join(root, "build/artifacts/old.exe"))); assert.equal(fs.readFileSync(path.join(root, "build/artifacts/user.txt"), "utf8"), "mine"); assert.equal(fs.readFileSync(path.join(first.runRoot, "outputs/artifacts/app.exe"), "utf8"), "one");
});
test("rejects missing provenance and preserves current outputs after failed exports", t => {
	const root = fixture(t), first = bundle(root, "first", { "build/artifacts/app.exe": "one" }); promote(root, first.runRoot, exportOutputs(first.runRoot, first.expected));
	const second = bundle(root, "second", { "build/artifacts/app.exe": "two" });
	assert.throws(() => exportOutputs(second.runRoot, { ...second.expected, source: "b".repeat(40) }), /provenance/); assert.equal(fs.readFileSync(path.join(root, "build/artifacts/app.exe"), "utf8"), "one");
});
test("protects unowned and user-modified outputs", t => {
	const root = fixture(t), run = bundle(root, "run", { "build/artifacts/app.exe": "one" }); fs.mkdirSync(path.join(root, "build/artifacts"), { recursive: true }); fs.writeFileSync(path.join(root, "build/artifacts/app.exe"), "mine");
	assert.throws(() => promote(root, run.runRoot, exportOutputs(run.runRoot, run.expected)), /ownership conflict/); assert.equal(fs.readFileSync(path.join(root, "build/artifacts/app.exe"), "utf8"), "mine");
});
test("rejects escaping archive paths, special TAR entries, duplicates and undeclared products", () => {
	for (const name of ["../secret", "C:/secret", "build/artifacts/CON.exe", "build/artifacts/file."]) assert.throws(() => unzip(Buffer.from(zipSync({ [name]: Buffer.from("x") }))), /Unsafe/);
	for (const type of ["1", "2", "3", "6"]) assert.throws(() => tar(archive([["build/artifacts/x", "", type]])), /forbidden/);
	assert.throws(() => tar(archive([[".workspace/secret", "x"]])), /namespace/);
	assert.throws(() => tar(archive([["build/artifacts/x", "x"], ["build/artifacts/x", "y"]])), /Duplicate/);
});
test("rejects corrupt hashes and missing component bundles", t => {
	const root = fixture(t), run = bundle(root, "run", { "build/artifacts/app.exe": "one" });
	assert.throws(() => exportOutputs(run.runRoot, { ...run.expected, components: ["missing"] }), /Missing component/);
});

test("recovers an interrupted promotion before publishing the next run", t => {
	const root = fixture(t), first = bundle(root, "first", { "build/artifacts/app.exe": "one" }); promote(root, first.runRoot, exportOutputs(first.runRoot, first.expected));
	const interrupted = path.join(root, "build/run/interrupted/promotion-backup/build/artifacts"); fs.mkdirSync(interrupted, { recursive: true });
	fs.renameSync(path.join(root, "build/artifacts/app.exe"), path.join(interrupted, "app.exe")); fs.writeFileSync(path.join(root, "build/artifacts/app.exe"), "two");
	fs.writeFileSync(path.join(root, ".workspace/ci/promotion.json"), JSON.stringify({ runId: "interrupted", paths: [{ path: "build/artifacts/app.exe", existed: true, nextHash: hash(Buffer.from("two")), oldHash: hash(Buffer.from("one")) }] }));
	const next = bundle(root, "next", { "build/artifacts/app.exe": "three" }); promote(root, next.runRoot, exportOutputs(next.runRoot, next.expected));
	assert.equal(fs.readFileSync(path.join(root, "build/artifacts/app.exe"), "utf8"), "three"); assert.ok(!fs.existsSync(path.join(root, ".workspace/ci/promotion.json")));
});

test("junction destinations cannot redirect promotion into local state", t => {
	const root = fixture(t), run = bundle(root, "run", { "build/artifacts/app.exe": "one" }); fs.mkdirSync(path.join(root, ".workspace/private"), { recursive: true });
	fs.symlinkSync(path.join(root, ".workspace/private"), path.join(root, "build/artifacts"), process.platform === "win32" ? "junction" : "dir");
	assert.throws(() => promote(root, run.runRoot, exportOutputs(run.runRoot, run.expected)), /Linked/); assert.ok(!fs.existsSync(path.join(root, ".workspace/private/app.exe")));
});

test("tampered hashes and files outside a producer's declaration cannot be exported", t => {
	const root = fixture(t), run = bundle(root, "run", { "build/artifacts/app.exe": "one" });
	const zip = path.join(run.runRoot, "transport/1/outputs-example/outputs-example.zip"), contents = unzip(fs.readFileSync(zip));
	const manifest = JSON.parse(Buffer.from(contents["manifest.json"]).toString("utf8")); manifest.files[0].sha256 = "0".repeat(64); contents["manifest.json"] = Buffer.from(JSON.stringify(manifest)); fs.writeFileSync(zip, zipSync(contents));
	assert.throws(() => exportOutputs(run.runRoot, run.expected), /corrupt product/);
	const other = bundle(root, "other", { "build/artifacts/app.exe": "one" });
	assert.throws(() => exportOutputs(other.runRoot, { ...other.expected, tasks: [{ identity: "example", outputs: ["build/artifacts/different.exe"] }] }), /declared component/);
});
