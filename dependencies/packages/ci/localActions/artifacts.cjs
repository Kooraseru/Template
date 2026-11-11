"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { unzipSync } = require("../../core/dependencyLoader/vendor/fflate.cjs");
const LIMIT = 512 * 1024 * 1024;
const hash = bytes => crypto.createHash("sha256").update(bytes).digest("hex");

function relative(name) {
	if (typeof name !== "string" || !name || name.includes("\\") || /[:\x00-\x1f]/.test(name) || name.startsWith("/") || name.split("/").some(part => part === "." || part === "..")) throw new Error("Unsafe artifact path: " + name);
	const normalized = name.replace(/\/$/, "");
	if (normalized.split("/").some(part => /[. ]$/.test(part) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i.test(part))) throw new Error("Unsafe Windows artifact path: " + name);
	return normalized;
}
function target(root, name) {
	const file = path.resolve(root, relative(name));
	const local = path.relative(path.resolve(root), file);
	if (!local || local.startsWith(".." + path.sep) || path.isAbsolute(local)) throw new Error("Artifact path escaped its root");
	let current = path.resolve(root);
	if (fs.lstatSync(current, { throwIfNoEntry: false })?.isSymbolicLink()) throw new Error("Linked artifact root");
	for (const part of local.split(path.sep)) {
		current = path.join(current, part);
		if (fs.lstatSync(current, { throwIfNoEntry: false })?.isSymbolicLink()) throw new Error("Linked artifact destination");
	}
	return file;
}
function product(name) {
	relative(name);
	if (!/^(build\/artifacts\/|build\/github\/).+/.test(name)) throw new Error("Undeclared product namespace: " + name);
	return name;
}
function write(root, name, bytes) {
	const file = target(root, name); fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, bytes, { flag: "wx" });
}
function unzip(bytes) {
	if (bytes.length > LIMIT) throw new Error("Oversized ZIP");
	let end = -1;
	for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) if (bytes.readUInt32LE(i) === 0x06054b50 && i + 22 + bytes.readUInt16LE(i + 20) === bytes.length) { end = i; break; }
	if (end < 0) throw new Error("Invalid ZIP");
	const count = bytes.readUInt16LE(end + 10); let offset = bytes.readUInt32LE(end + 16), total = 0;
	if (count > 20000 || offset === 0xffffffff) throw new Error("Unsupported ZIP size");
	const names = new Set();
	for (let i = 0; i < count; i++) {
		if (offset + 46 > bytes.length || bytes.readUInt32LE(offset) !== 0x02014b50) throw new Error("Invalid ZIP directory");
		const size = bytes.readUInt32LE(offset + 24), length = bytes.readUInt16LE(offset + 28), extra = bytes.readUInt16LE(offset + 30), comment = bytes.readUInt16LE(offset + 32);
		const name = relative(bytes.toString("utf8", offset + 46, offset + 46 + length));
		if (names.has(name.toLowerCase()) || ((bytes.readUInt32LE(offset + 38) >>> 16) & 0xf000) === 0xa000) throw new Error("Duplicate or linked ZIP entry");
		names.add(name.toLowerCase()); total += size;
		if (total > LIMIT) throw new Error("ZIP exceeds export limit");
		offset += 46 + length + extra + comment;
	}
	return unzipSync(bytes);
}
function tar(bytes) {
	if (bytes.length > LIMIT) throw new Error("Oversized TAR");
	const entries = new Map(); let pax;
	for (let offset = 0, count = 0; offset + 512 <= bytes.length;) {
		const header = bytes.subarray(offset, offset + 512); if (header.every(byte => byte === 0)) break;
		const text = (start, size) => header.subarray(start, start + size).toString("utf8").replace(/\0.*$/s, "");
		const sizeText = text(124, 12).trim();
		if (!/^[0-7]+$/.test(sizeText)) throw new Error("Invalid TAR size");
		const checksum = header.subarray(148, 156).toString("ascii").replace(/\0/g, "").trim();
		const actualChecksum = header.reduce((sum, byte, index) => sum + (index >= 148 && index < 156 ? 32 : byte), 0);
		if (!/^[0-7]+$/.test(checksum) || parseInt(checksum, 8) !== actualChecksum) throw new Error("Invalid TAR checksum");
		const size = parseInt(sizeText, 8), type = String.fromCharCode(header[156] || 48), data = bytes.subarray(offset + 512, offset + 512 + size);
		if (data.length !== size || ++count > 20000) throw new Error("Truncated TAR");
		if (type === "x") {
			pax = undefined;
			for (const line of data.toString("utf8").split("\n")) { const match = line.match(/^\d+ path=(.*)$/); if (match) pax = match[1]; }
		} else if (type !== "g") {
			const name = relative(pax || (text(345, 155) ? text(345, 155) + "/" : "") + text(0, 100)); pax = undefined;
			if (!["0", "5"].includes(type)) throw new Error("Links and special TAR files are forbidden");
			if (type === "0") { product(name); if (entries.has(name)) throw new Error("Duplicate TAR file"); entries.set(name, data); }
		}
		offset += 512 + Math.ceil(size / 512) * 512;
	}
	return entries;
}
function walk(root) {
	if (!fs.existsSync(root)) return [];
	const result = [];
	for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
		if (entry.isSymbolicLink()) throw new Error("Linked transport entry");
		const file = path.join(root, entry.name);
		if (entry.isDirectory()) result.push(...walk(file)); else if (entry.isFile()) result.push(file);
	}
	return result;
}
function receiveStart(runRoot) {
	const archives = walk(path.join(runRoot, "transport")).filter(file => path.basename(file) === "start.zip");
	if (archives.length !== 1) throw new Error("Expected exactly one Start artifact");
	for (const [name, bytes] of Object.entries(unzip(fs.readFileSync(archives[0])))) if (!name.endsWith("/")) write(path.join(runRoot, "start"), name, bytes);
	return path.join(runRoot, "start/workflows");
}
function receiveDiagnostics(runRoot) {
	for (const archive of walk(path.join(runRoot, "transport")).filter(file => file.endsWith(".zip"))) {
		const name = path.basename(archive, ".zip");
		const match = name.match(/^(logs|response|report)-(validation|build|publish|readiness)(?:-|$)/);
		if (!match) continue;
		const directory = path.join(runRoot, match[2], ...(match[1] === "report" ? [] : [match[1] === "logs" ? "logs" : "responses"]));
		for (const [file, bytes] of Object.entries(unzip(fs.readFileSync(archive)))) {
			if (file.endsWith("/")) continue;
			const destination = target(directory, file);
			if (fs.existsSync(destination)) { if (hash(fs.readFileSync(destination)) !== hash(bytes)) throw new Error("Diagnostic output collision"); }
			else write(directory, file, bytes);
		}
	}
}
function exportOutputs(runRoot, expected) {
	const directory = path.join(runRoot, "outputs"); fs.mkdirSync(directory, { recursive: true });
	const files = [], components = [], owned = new Set();
	for (const archive of walk(path.join(runRoot, "transport")).filter(file => path.basename(file).startsWith("outputs-") && file.endsWith(".zip"))) {
		const contents = unzip(fs.readFileSync(archive));
		const manifest = JSON.parse(Buffer.from(contents["manifest.json"] || []).toString("utf8"));
		if (manifest.version !== 1 || !manifest.complete || !["passed", "skipped"].includes(manifest.outcome) || manifest.runId !== expected.runId || manifest.source !== expected.source || (expected.workspaceDigest && manifest.workspaceDigest !== expected.workspaceDigest) || manifest.operation !== expected.operation || manifest.phase !== "build" || !Array.isArray(manifest.files)) throw new Error("Output provenance mismatch");
		const task = expected.tasks?.find(task => task.identity === manifest.component);
		if (expected.tasks && !task) throw new Error("Unknown producing component");
		const data = tar(Buffer.from(contents["outputs.tar"] || []));
		if (data.size !== manifest.files.length) throw new Error("Manifest does not cover every TAR file");
		for (const item of manifest.files) {
			product(item.path); if (task && !task.outputs.some(pattern => path.posix.matchesGlob(item.path, pattern))) throw new Error("File outside declared component outputs"); const key = item.path.toLowerCase(), bytes = data.get(item.path);
			if (owned.has(key) || !bytes || bytes.length !== item.size || hash(bytes) !== item.sha256) throw new Error("Duplicate, missing or corrupt product");
			owned.add(key); write(directory, item.path.slice(6), bytes); files.push(item);
		}
		components.push(manifest.component);
	}
	if (expected.components && (components.length !== expected.components.length || expected.components.some(id => !components.includes(id)))) throw new Error("Missing component outputs");
	const manifest = { version: 1, ...expected, complete: true, outcome: "passed", files, components };
	fs.writeFileSync(path.join(directory, "manifest.json"), JSON.stringify(manifest, null, 2));
	return manifest;
}

// Promotion only touches manifest-owned products. A journal makes interrupted changes reversible.
function promote(root, runRoot, manifest) {
	const stateRoot = path.join(root, ".workspace/ci"); fs.mkdirSync(stateRoot, { recursive: true });
	const lock = path.join(stateRoot, "promotion-lock");
	try { fs.mkdirSync(lock); }
	catch (error) {
		if (error.code !== "EEXIST") throw error;
		const ownerFile = path.join(lock, "owner.json");
		let dead = false;
		try { const owner = JSON.parse(fs.readFileSync(ownerFile, "utf8")); if (!Number.isInteger(owner.pid) || owner.pid < 1) throw new Error("Invalid promotion owner"); try { process.kill(owner.pid, 0); } catch (failure) { dead = failure.code === "ESRCH"; } }
		catch { dead = Date.now() - fs.statSync(lock).mtimeMs > 60000; }
		if (!dead) throw new Error("Another output promotion is active; retry after it finishes");
		fs.rmSync(ownerFile, { force: true }); fs.rmdirSync(lock); fs.mkdirSync(lock);
	}
	fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: process.pid }));
	const stateFile = path.join(stateRoot, "current-outputs.json"), journalFile = path.join(stateRoot, "promotion.json");
	function rollback(journal) {
		if (fs.existsSync(stateFile) && JSON.parse(fs.readFileSync(stateFile, "utf8")).runId === journal.runId) { fs.rmSync(journalFile); return; }
		if (!/^[a-zA-Z0-9_-]+$/.test(journal.runId) || !Array.isArray(journal.paths)) throw new Error("Invalid promotion journal");
		const previousRoot = target(root, "build/run/" + journal.runId + "/promotion-backup");
		for (const item of [...journal.paths].reverse()) {
			product(item.path); const dest = target(root, item.path), backup = target(previousRoot, item.path);
			if (fs.existsSync(backup)) { if ((fs.existsSync(dest) && item.nextHash && hash(fs.readFileSync(dest)) !== item.nextHash) || (item.oldHash && hash(fs.readFileSync(backup)) !== item.oldHash)) throw new Error("Recovery ownership conflict: " + item.path); fs.rmSync(dest, { force: true }); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.renameSync(backup, dest); }
			else if (!item.existed) { if (fs.existsSync(dest) && item.nextHash && hash(fs.readFileSync(dest)) !== item.nextHash) throw new Error("Recovery ownership conflict: " + item.path); fs.rmSync(dest, { force: true }); }
		}
		fs.rmSync(journalFile);
	}
	try {
		if (fs.existsSync(journalFile)) rollback(JSON.parse(fs.readFileSync(journalFile, "utf8")));
		const old = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, "utf8")) : { files: [] };
		const previous = new Map(old.files.map(item => [product(item.path), item]));
		const next = new Map(manifest.files.map(item => [product(item.path), item]));
		const paths = [...new Set([...previous.keys(), ...next.keys()])].sort().map(name => {
			const dest = target(root, name), stat = fs.lstatSync(dest, { throwIfNoEntry: false });
			if (stat && (!stat.isFile() || !previous.has(name) || hash(fs.readFileSync(dest)) !== previous.get(name).sha256)) throw new Error("Output ownership conflict: " + name);
			return { path: name, existed: !!stat, nextHash: next.get(name)?.sha256, oldHash: previous.get(name)?.sha256 };
		});
		const journal = { runId: manifest.runId, paths }; fs.writeFileSync(journalFile, JSON.stringify(journal), { flag: "wx" });
		try {
			for (const item of paths) {
				const dest = target(root, item.path), backup = target(path.join(runRoot, "promotion-backup"), item.path);
				if (item.existed) { fs.mkdirSync(path.dirname(backup), { recursive: true }); fs.renameSync(dest, backup); }
				if (next.has(item.path)) { const source = target(path.join(runRoot, "outputs"), item.path.slice(6)); const bytes = fs.readFileSync(source); if (hash(bytes) !== next.get(item.path).sha256) throw new Error("Snapshot changed before promotion"); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, bytes, { flag: "wx" }); }
			}
			fs.writeFileSync(stateFile + ".tmp", JSON.stringify(manifest)); fs.renameSync(stateFile + ".tmp", stateFile); fs.rmSync(journalFile);
		} catch (error) { rollback(journal); throw error; }
	} finally { fs.unlinkSync(path.join(lock, "owner.json")); fs.rmdirSync(lock); }
}
function snapshot(root) {
	const { execFileSync } = require("node:child_process");
	const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: root, windowsHide: true, stdio: ["ignore", "pipe", "ignore"] }).toString().split("\0").filter(Boolean);
	const files = tracked.map(name => { const file = target(root, name); return [name, fs.existsSync(file) ? fs.readFileSync(file) : null]; });
	const digest = hash(Buffer.concat(files.flatMap(([name, bytes]) => [Buffer.from(name + "\0"), bytes || Buffer.from("deleted"), Buffer.from("\0")])));
	return { tracked, files, digest };
}
module.exports = { receiveDiagnostics, snapshot, relative, target, unzip, tar, receiveStart, exportOutputs, promote, hash };
