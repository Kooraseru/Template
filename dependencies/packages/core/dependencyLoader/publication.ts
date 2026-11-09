import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { setTimeout } from "node:timers/promises";
import { contained, json, readJson, relativePath, within } from "./contract.ts";

const journalName = ".loader-journal.json";
export const stateName = ".loader-state.json";

export function atomicJson(file: string, value: unknown) {
	const temporary = file + "." + crypto.randomUUID() + ".tmp";
	try {
		fs.writeFileSync(temporary, json(value), { flag: "wx" });
		fs.renameSync(temporary, file);
	} finally { fs.rmSync(temporary, { force: true }); }
}

export function outputPath(value: unknown): string {
	const output = relativePath(value);
	if (output.startsWith(".")) throw new Error("Reserved dependency output: " + output);
	return output;
}

export function overlaps(left: string, right: string) {
	left = left.toLowerCase();
	right = right.toLowerCase();
	return left === right || left.startsWith(right + "/") || right.startsWith(left + "/");
}

export function checkTree(root: string) {
	function visit(entry: string) {
		const stat = fs.lstatSync(entry);
		if (stat.isSymbolicLink()) {
			const link = fs.readlinkSync(entry);
			const target = path.resolve(path.dirname(entry), link);
			if (path.isAbsolute(link) || !within(root, target) || !within(root, fs.realpathSync(target))) {
				throw new Error("Staged output contains an escaping or absolute symlink: " + entry);
			}
		} else if (stat.isDirectory()) {
			for (const child of fs.readdirSync(entry)) visit(path.join(entry, child));
		} else if (!stat.isFile()) throw new Error("Unsupported staged output: " + entry);
	}
	visit(root);
}

type Change = { to: string; source?: string; existed: boolean };
type Journal = { stage: string; changes: Change[] };

function recover(generated: string) {
	const journalFile = contained(generated, journalName);
	if (!fs.existsSync(journalFile)) return;
	const journal = readJson(journalFile) as Journal;
	if (!/^\.loader-stage-[\w-]+$/.test(journal.stage) || !Array.isArray(journal.changes)) throw new Error("Invalid dependency publication journal");
	const stage = contained(generated, journal.stage);
	const state = contained(generated, stateName);
	const committed = fs.existsSync(state) && (readJson(state) as { transaction?: string }).transaction === journal.stage;
	if (!committed) {
		for (let index = journal.changes.length - 1; index >= 0; index--) {
			const change = journal.changes[index];
			const target = contained(generated, outputPath(change.to));
			const backup = contained(stage, ".backup/" + index);
			const source = change.source === undefined ? undefined : contained(stage, change.source);
			if (fs.existsSync(backup)) {
				fs.rmSync(target, { recursive: true, force: true });
				fs.renameSync(backup, target);
			} else if (!change.existed && source && !fs.existsSync(source)) {
				fs.rmSync(target, { recursive: true, force: true });
			}
		}
	}
	fs.unlinkSync(journalFile);
	fs.rmSync(stage, { recursive: true, force: true });
}

export function publish(generated: string, stage: string, entries: unknown, outputs: Map<string, string | undefined>) {
	const changes: Change[] = [];
	for (const [to, source] of outputs) {
		const target = contained(generated, outputPath(to));
		const existed = fs.existsSync(target);
		if (!source && !existed) continue;
		if (source && !within(stage, source)) throw new Error("Output is outside the transaction stage");
		changes.push({ to, source: source && path.relative(stage, source).split(path.sep).join("/"), existed });
	}
	const transaction = path.basename(stage);
	if (!changes.length) {
		atomicJson(contained(generated, stateName), { transaction, entries });
		return;
	}
	const backup = path.join(stage, ".backup");
	fs.mkdirSync(backup);
	atomicJson(contained(generated, journalName), { stage: transaction, changes });
	try {
		for (const [index, change] of changes.entries()) {
			const target = contained(generated, change.to);
			if (change.existed) fs.renameSync(target, path.join(backup, String(index)));
			if (change.source) {
				fs.mkdirSync(path.dirname(target), { recursive: true });
				fs.renameSync(contained(stage, change.source), target);
			}
		}
		atomicJson(contained(generated, stateName), { transaction, entries });
	} finally {
		recover(generated);
	}
}

function ownerAlive(pid: number): boolean {
	try { process.kill(pid, 0); return true; }
	catch (error) { return (error as NodeJS.ErrnoException).code !== "ESRCH"; }
}

function removeEmpty(directory: string) {
	try { fs.rmdirSync(directory); }
	catch (error) {
		if (!["ENOENT", "ENOTEMPTY", "EEXIST"].includes((error as NodeJS.ErrnoException).code || "")) throw error;
	}
}

export async function withStage<T>(generated: string, work: (stage: string) => Promise<T>): Promise<T> {
	fs.mkdirSync(generated, { recursive: true });
	const mutex = contained(generated, ".loader-lock");
	const token = "owner-" + process.pid + "-" + crypto.randomUUID();
	const owner = path.join(mutex, token);
	const candidate = fs.mkdtempSync(path.join(generated, ".loader-owner-"));
	fs.writeFileSync(path.join(candidate, token), "");
	const deadline = Date.now() + 240_000;
	let acquired = false;
	try {
		for (;;) {
			try { fs.renameSync(candidate, mutex); acquired = true; break; }
			catch (error) {
				if (!fs.existsSync(mutex) && !["EEXIST", "EPERM", "ENOTEMPTY"].includes((error as NodeJS.ErrnoException).code || "")) throw error;
			}
			let previous: string | undefined;
			try { previous = fs.readdirSync(mutex).find(name => /^owner-\d+-[a-f0-9-]+$/.test(name)); }
			catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
			if (previous === undefined) removeEmpty(mutex);
			else {
				const pid = Number(previous.split("-")[1]);
				if (Number.isSafeInteger(pid) && pid > 0 && !ownerAlive(pid)) {
					fs.rmSync(path.join(mutex, previous), { force: true });
					removeEmpty(mutex);
				}
			}
			if (Date.now() >= deadline) throw new Error("Timed out waiting for dependency setup to finish");
			await setTimeout(200);
		}
		recover(generated);
		const stage = fs.mkdtempSync(path.join(generated, ".loader-stage-"));
		try { return await work(stage); }
		finally {
			if (!fs.existsSync(path.join(generated, journalName))) fs.rmSync(stage, { recursive: true, force: true });
		}
	} finally {
		if (fs.existsSync(candidate)) fs.rmSync(candidate, { recursive: true, force: true });
		if (acquired) {
			fs.unlinkSync(owner);
			removeEmpty(mutex);
		}
	}
}
