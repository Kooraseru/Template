import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export type RecordValue = Record<string, unknown>;
export type Output = { from: string; to: string };
export type Export = { root: "workspace" | "build"; path: string };
export type Executable = { export: string; interpreter?: string[] };
export type Installation = { outputs: Output[]; exports?: Record<string, Export>; executable?: Executable };
export type ProviderRequest = {
	action: "resolve" | "install";
	id: string;
	options: RecordValue;
	workspace: string;
	platform: string;
	arch: string;
	stage: string;
	prerequisites: Record<string, Record<string, string>>;
	previous?: unknown;
	resolution?: unknown;
};
export type Provider = {
	resolve(request: ProviderRequest): unknown | Promise<unknown>;
	install(request: ProviderRequest): Installation | Promise<Installation>;
};

export function record(value: unknown, message: string): RecordValue {
	if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(message);
	return value as RecordValue;
}

export function text(value: unknown, label: string): string {
	if (typeof value !== "string" || !value || value.includes("\0")) throw new Error("Invalid " + label);
	return value;
}

export function args(value: unknown, label: string): string[] {
	if (!Array.isArray(value) || !value.length || typeof value[0] !== "string" || !value[0]
		|| value.some(item => typeof item !== "string" || item.includes("\0"))) throw new Error("Invalid " + label);
	return value;
}

export function within(base: string, candidate: string): boolean {
	const relative = path.relative(base, candidate);
	return relative !== "" && relative !== ".." && !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative);
}

export function relativePath(value: unknown): string {
	const relative = text(value, "relative path");
	if (relative.split("/").some(part => !part || part === "." || part === ".." || /[<>:"\\|?*\x00-\x1f]|[. ]$/.test(part)
		|| /^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part))) throw new Error("Unsafe relative path: " + relative);
	return relative;
}

export function contained(base: string, relative: unknown): string {
	let current = base;
	for (const segment of relativePath(relative).split("/")) {
		current = path.join(current, segment);
		if (fs.lstatSync(current, { throwIfNoEntry: false })?.isSymbolicLink()) {
			throw new Error("Dependency path contains a symlink: " + current);
		}
	}
	return current;
}

export function digest(value: unknown): string {
	function ordered(item: unknown): unknown {
		if (Array.isArray(item)) return item.map(ordered);
		if (item && typeof item === "object") {
			return Object.fromEntries(Object.entries(item).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
				.map(([key, value]) => [key, ordered(value)]));
		}
		return item;
	}
	return crypto.createHash("sha256").update(JSON.stringify(ordered(value))).digest("hex");
}

export function json(value: unknown): string {
	return JSON.stringify(value, null, 2) + "\n";
}

export function readJson(file: string): unknown {
	return JSON.parse(fs.readFileSync(file, "utf8"));
}
