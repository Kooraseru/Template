import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { args, contained, digest, readJson, record, relativePath, text, type Executable, type Export, type Provider, type ProviderRequest, type RecordValue } from "./contract.ts";
import { providerFrom } from "./providers.ts";
import { atomicJson, checkTree, outputPath, overlaps, publish, stateName } from "./publication.ts";
import { legacyOutputs } from "./legacy.ts";

type Definition = { id: string; provider: string; options: RecordValue; needs: string[] };
type LockEntry = { provider: string; fingerprint: string; resolution: unknown };
type Installed = { fingerprint?: string; outputs: string[]; exports: Record<string, Export>; executable?: Executable };
type Prepared = { installed: Installed; exports: Record<string, string>; paths: Map<string, string> };
type Progress = (message: string, completed: number, total: number, detail?: string) => void;

export const lockVersion = 2;

export function lockFingerprint(registration: unknown, dependency: Definition, prerequisites: [string, LockEntry][], inputs: [string, string][] = []) {
	return digest({ registration, dependency, prerequisites, inputs });
}

function identifier(value: string) {
	if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(value)) throw new Error("Invalid dependency or provider ID: " + value);
	return value;
}

function manifest(workspace: string) {
	const config = record(readJson(contained(workspace, "dependencies/dependencies.json")), "Invalid dependency manifest");
	if (Object.keys(config).some(key => !["providers", "dependencies"].includes(key))) throw new Error("Unexpected dependency manifest field");
	const registrations = record(config.providers, "Expected dependency providers");
	const providers = new Map<string, { registration: RecordValue; implementation: Provider; inputs: [string, string][] }>();
	for (const [name, value] of Object.entries(registrations)) {
		const registration = record(value, "Invalid provider: " + name);
		const implementation = providerFrom(registration);
		const files = new Set<string>();
		const declared = registration.inputs === undefined ? [] : registration.inputs;
		if (!Array.isArray(declared) || new Set(declared).size !== declared.length) throw new Error("Provider inputs must be a list of unique paths: " + name);
		for (const input of declared) files.add(relativePath(input));
		if (Array.isArray(registration.command)) {
			for (const argument of registration.command) {
				// A workspace script named directly by the command is an implicit input.
				if (typeof argument !== "string" || !argument.includes("/") || argument.startsWith("-")) continue;
				const candidate = argument.replace(/^\.\//, "");
				let file: string;
				try { file = contained(workspace, candidate); } catch { continue; }
				if (fs.statSync(file, { throwIfNoEntry: false })?.isFile()) files.add(candidate);
			}
		}
		const inputs: [string, string][] = [...files].sort().map(file => [
			file, crypto.createHash("sha256").update(fs.readFileSync(contained(workspace, file))).digest("hex"),
		]);
		providers.set(identifier(name), { registration, implementation, inputs });
	}
	const definitions = new Map<string, Definition>();
	for (const [id, value] of Object.entries(record(config.dependencies, "Expected dependency definitions"))) {
		const definition = record(value, "Invalid dependency: " + id);
		if (Object.keys(definition).some(key => !["provider", "needs", "options"].includes(key))) throw new Error("Unexpected dependency field: " + id);
		const provider = text(definition.provider, "provider for " + id);
		if (!providers.has(provider)) throw new Error(id + " uses unknown provider " + provider);
		const needs = definition.needs === undefined ? [] : definition.needs;
		if (!Array.isArray(needs) || needs.some(need => typeof need !== "string") || new Set(needs).size !== needs.length) {
			throw new Error("Invalid prerequisites for " + id);
		}
		const options = record(definition.options === undefined ? {} : definition.options, "Invalid options for " + id);
		definitions.set(identifier(id), { id, provider, options, needs });
	}
	const ordered: Definition[] = [];
	const visited = new Set<string>();
	function visit(id: string, chain: string[]) {
		if (visited.has(id)) return;
		if (chain.includes(id)) throw new Error("Dependency cycle: " + [...chain, id].join(" -> "));
		const definition = definitions.get(id);
		if (!definition) throw new Error("Missing prerequisite " + id + " for " + chain.at(-1));
		for (const prerequisite of definition.needs) visit(prerequisite, [...chain, id]);
		visited.add(id);
		ordered.push(definition);
	}
	for (const id of definitions.keys()) visit(id, []);
	return { providers, ordered };
}

function readLock(file: string, update: boolean): Map<string, LockEntry> {
	if (!fs.existsSync(file) && update) return new Map();
	if (!fs.existsSync(file)) throw new Error("Missing dependencies.lock; run --update-lock");
	const lock = record(readJson(file), "Invalid dependencies.lock; run --update-lock");
	if (lock.version !== lockVersion) {
		if (update) return new Map();
		throw new Error("Unsupported dependencies.lock format; run --update-lock");
	}
	return new Map(Object.entries(record(lock.entries, "Invalid dependencies.lock entries; run --update-lock"))) as Map<string, LockEntry>;
}

function exportDefinitions(value: unknown): Record<string, Export> {
	return Object.fromEntries(Object.entries(record(value ?? {}, "Invalid provider exports")).map(([name, value]) => {
		const entry = record(value, "Invalid export " + name);
		if (entry.root !== "workspace" && entry.root !== "build") throw new Error("Invalid export root for " + name);
		return [name, { root: entry.root, path: relativePath(entry.path) }];
	}));
}

function executableDefinition(value: unknown, exports: Record<string, Export>): Executable | undefined {
	if (value === undefined) return;
	const entry = record(value, "Invalid provider executable");
	const name = text(entry.export, "executable export");
	if (!Object.hasOwn(exports, name)) throw new Error("Unknown executable export: " + name);
	return { export: name, interpreter: entry.interpreter === undefined ? undefined : args(entry.interpreter, "executable interpreter") };
}

function readInstalled(generated: string): Map<string, Installed> {
	const file = contained(generated, stateName);
	if (!fs.existsSync(file)) {
		return new Map(Object.entries(legacyOutputs(generated)).map(([id, outputs]) => [id, { outputs, exports: {} }]));
	}
	const state = record(readJson(file), "Invalid dependency installation state");
	return new Map(Object.entries(record(state.entries, "Invalid dependency installation entries")).map(([id, value]) => {
		const entry = record(value, "Invalid dependency installation: " + id);
		if (!Array.isArray(entry.outputs)) throw new Error("Invalid installed output list: " + id);
		const exports = exportDefinitions(entry.exports);
		return [id, {
			fingerprint: typeof entry.fingerprint === "string" ? entry.fingerprint : undefined,
			outputs: entry.outputs.map(outputPath),
			exports, executable: executableDefinition(entry.executable, exports),
		}];
	}));
}

function outputRoot(outputs: string[], location: string) {
	return outputs.find(output => location === output || location.startsWith(output + "/"));
}

function absoluteExports(workspace: string, generated: string, install: Installed, staged?: Map<string, string>) {
	const values: Record<string, string> = Object.create(null);
	for (const [name, value] of Object.entries(install.exports)) {
		let resolved: string;
		if (value.root === "workspace") {
			if (value.path === "build" || value.path.startsWith("build/")) throw new Error("Use a build export for generated output: " + value.path);
			resolved = contained(workspace, value.path);
		} else {
			const output = outputRoot(install.outputs, value.path);
			if (!output) throw new Error("Export is outside declared outputs: " + value.path);
			const root = staged?.get(output) ?? contained(generated, output);
			const relative = value.path.slice(output.length + 1);
			resolved = relative ? contained(root, relative) : root;
		}
		const stat = fs.statSync(resolved, { throwIfNoEntry: false });
		if (!stat || (name === install.executable?.export && !stat.isFile())) throw new Error("Missing dependency export: " + resolved);
		values[name] = resolved;
	}
	return values;
}

function checkedInstallation(result: unknown, stage: string, fingerprint: string): { installed: Installed; paths: Map<string, string> } {
	const value = record(result, "Invalid installation response");
	if (!Array.isArray(value.outputs)) throw new Error("Provider must return an outputs array");
	const paths = new Map<string, string>();
	const sources: string[] = [];
	for (const item of value.outputs) {
		const output = record(item, "Invalid provider output");
		const from = relativePath(output.from);
		const to = outputPath(output.to);
		if ([...paths.keys()].some(other => overlaps(to, other)) || sources.some(other => overlaps(from, other))) {
			throw new Error("Conflicting provider output: " + to);
		}
		const absolute = contained(stage, from);
		checkTree(absolute);
		paths.set(to, absolute);
		sources.push(from);
	}
	const exports = exportDefinitions(value.exports);
	return { installed: { fingerprint, outputs: [...paths.keys()], exports, executable: executableDefinition(value.executable, exports) }, paths };
}

export async function load(workspace: string, generated: string, stage: string, update: boolean, progress: Progress, requested?: string, only?: string[]) {
	const { providers, ordered } = manifest(workspace);
	if (requested && !ordered.some(dependency => dependency.id === requested)) throw new Error("Unknown dependency: " + requested);
	const lockFile = contained(workspace, "dependencies/dependencies.lock");
	const previous = readLock(lockFile, update);
	const old = readInstalled(generated);
	const next = new Map<string, LockEntry>();
	const prepared = new Map<string, Prepared>();
	const fingerprints = new Map<string, string>();
	const needed = new Set(ordered.flatMap(dependency => dependency.needs));

	async function call(provider: Provider, request: ProviderRequest) {
		try { return await provider[request.action](request); }
		catch (error) {
			throw new Error(request.id + " " + request.action + " failed: " + (error instanceof Error ? error.message : String(error)), { cause: error });
		}
	}
	function context(dependency: Definition, action: ProviderRequest["action"]): ProviderRequest {
		const directory = fs.mkdtempSync(path.join(stage, action + "-"));
		const prerequisites = Object.fromEntries(dependency.needs.map(id => [id, prepared.get(id)!.exports]));
		return { action, id: dependency.id, options: dependency.options, workspace, stage: directory, platform: process.platform, arch: process.arch, prerequisites };
	}
	function declaredFingerprint(dependency: Definition) {
		const provider = providers.get(dependency.provider)!;
		return lockFingerprint(provider.registration, dependency, dependency.needs.map(id => [id, next.get(id)!]), provider.inputs);
	}
	async function prepare(dependency: Definition) {
		const entry = next.get(dependency.id)!;
		const fingerprint = digest({
			entry, platform: process.platform, arch: process.arch, node: process.version,
			needs: dependency.needs.map(id => fingerprints.get(id)),
		});
		fingerprints.set(dependency.id, fingerprint);
		const cached = old.get(dependency.id);
		if (cached?.fingerprint === fingerprint && cached.outputs.every(output => fs.existsSync(contained(generated, output)))) {
			try {
				prepared.set(dependency.id, { installed: cached, exports: absoluteExports(workspace, generated, cached), paths: new Map() });
				return;
			} catch { /* Missing exports require a fresh install. */ }
		}
		const request = context(dependency, "install");
		request.resolution = entry.resolution;
		const result = await call(providers.get(dependency.provider)!.implementation, request);
		const { installed, paths } = checkedInstallation(result, request.stage, fingerprint);
		prepared.set(dependency.id, { installed, paths, exports: absoluteExports(workspace, generated, installed, paths) });
	}

	if (update) {
		for (const [index, dependency] of ordered.entries()) {
			progress("Resolving dependencies", index, ordered.length, dependency.id);
			const fingerprint = declaredFingerprint(dependency);
			const request = context(dependency, "resolve");
			const prior = previous.get(dependency.id);
			if (prior?.provider === dependency.provider) request.previous = prior.resolution;
			const resolution = await call(providers.get(dependency.provider)!.implementation, request);
			if (resolution === undefined) throw new Error("Provider returned no resolution: " + dependency.id);
			next.set(dependency.id, { provider: dependency.provider, fingerprint, resolution });
			if (needed.has(dependency.id)) await prepare(dependency);
		}
		atomicJson(lockFile, { version: lockVersion, entries: Object.fromEntries(next) });
		return undefined;
	}

	for (const dependency of ordered) {
		const entry = previous.get(dependency.id);
		const fingerprint = declaredFingerprint(dependency);
		if (!entry || entry.provider !== dependency.provider || entry.fingerprint !== fingerprint || !Object.hasOwn(entry, "resolution")) {
			throw new Error("Missing or stale lock entry for " + dependency.id + "; run --update-lock");
		}
		next.set(dependency.id, entry);
	}
	if (previous.size !== next.size) throw new Error("dependencies.lock contains removed dependencies; run --update-lock");

	const selectedIds = new Set<string>();
	if (only) {
		const byId = new Map(ordered.map(dependency => [dependency.id, dependency]));
		const include = (id: string) => {
			if (selectedIds.has(id)) return;
			const dependency = byId.get(id);
			if (!dependency) throw new Error("Unknown dependency: " + id);
			selectedIds.add(id);
			dependency.needs.forEach(include);
		};
		only.forEach(include);
		if (requested) include(requested);
	}
	const selected = only ? ordered.filter(dependency => selectedIds.has(dependency.id)) : ordered;
	for (const [index, dependency] of selected.entries()) {
		progress("Loading dependencies", index, selected.length, dependency.id);
		await prepare(dependency);
	}
	const owned = [...old].flatMap(([id, entry]) => entry.outputs.map(output => ({ id, output })));
	const destinations: { id: string; output: string }[] = [];
	const changes = new Map<string, string | undefined>();
	for (const [id, item] of prepared) {
		for (const output of item.installed.outputs) {
			const conflict = destinations.find(other => overlaps(output, other.output));
			if (conflict) throw new Error("Conflicting output " + output + " from " + id + " and " + conflict.id + " (" + conflict.output + ")");
			const prior = owned.find(other => overlaps(output, other.output));
			if (prior && (prior.id !== id || prior.output !== output)) {
				throw new Error("Output " + output + " from " + id + " conflicts with installed output " + prior.output + " from " + prior.id);
			}
			if (!prior && fs.existsSync(contained(generated, output))) throw new Error("Output directory or file is not owned by the dependency loader: " + output);
			destinations.push({ id, output });
			if (item.paths.has(output)) changes.set(output, item.paths.get(output));
		}
	}
	for (const { id, output } of owned) {
		if ((!only || selectedIds.has(id)) && !destinations.some(destination => destination.output === output)) changes.set(output, undefined);
	}
	const installed = new Map(only ? old : []);
	for (const [id, item] of prepared) installed.set(id, item.installed);
	if (changes.size || !fs.existsSync(contained(generated, stateName)) ||
		digest(Object.fromEntries(old)) !== digest(Object.fromEntries(installed))) {
		publish(generated, stage, Object.fromEntries(installed), changes);
	}
	progress("Dependencies ready", selected.length, selected.length);
	if (requested) {
		const install = prepared.get(requested)!.installed;
		if (!install.executable) throw new Error("Dependency has no executable: " + requested);
		return { path: absoluteExports(workspace, generated, install)[install.executable.export], interpreter: install.executable.interpreter };
	}
	return undefined;
}
