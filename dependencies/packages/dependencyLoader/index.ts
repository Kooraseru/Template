"use strict";

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parse } from "./vendor/toml.cjs";
import { extract } from "./archive.ts";
import { updateLock } from "./lock.ts";

const root = path.resolve(
	path.dirname(fileURLToPath(import.meta.url)),
	"../../..",
);
const dependencies = path.join(root, "dependencies");
const generated = path.join(root, "build", "dependencies");
const lockPath = path.join(dependencies, "dependencies.lock");
const platform = `${process.platform}-${process.arch}`;

export function within(base: string, candidate: string) {
	const relative = path.relative(path.resolve(base), path.resolve(candidate));
	return (
		relative !== "" &&
		relative !== ".." &&
		!relative.startsWith(`..${path.sep}`) &&
		!path.isAbsolute(relative)
	);
}

function managedPath(relative: string) {
	if (typeof relative !== "string" || path.isAbsolute(relative))
		throw new Error("Dependency path must be relative");
	const target = path.resolve(generated, relative);
	if (!within(generated, target))
		throw new Error(
			`Generated dependency path escapes build/dependencies: ${relative}`,
		);
	let current = generated;
	for (const part of path.relative(generated, target).split(path.sep)) {
		current = path.join(current, part);
		if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink())
			throw new Error(`Managed dependency path contains a symlink: ${current}`);
	}
	return target;
}

function removeStage(stage: string) {
	if (
		!within(os.tmpdir(), stage) ||
		!path.basename(stage).startsWith("workspace-dependency-")
	)
		throw new Error("Refusing to remove an unsafe staging path");
	fs.rmSync(stage, { recursive: true, force: true });
}

type DependencySpec = {
	source?: string;
	package?: string;
	path?: string;
	binaryPath?: string;
	typesPath?: string;
	version?: string | number;
	assets?: Record<string, string>;
	executables?: Record<string, string>;
	setup?: string[];
	setupAliases?: Record<string, string>;
};
type ReleaseAsset = {
	name: string;
	digest?: string;
	browser_download_url: string;
};
type LockedDependency = {
	version: string;
	platforms?: Record<
		string,
		{ asset: string; url: string; digest: string; executable?: string }
	>;
	npm?: {
		url: string;
		integrity: string;
		dependencies?: Record<string, string>;
	};
};
type Lock = { version: 1; dependencies: Record<string, LockedDependency> };

function readLock(): Lock {
	const lock = JSON.parse(fs.readFileSync(lockPath, "utf8")) as Lock;
	if (
		lock.version !== 1 ||
		!lock.dependencies ||
		typeof lock.dependencies !== "object"
	)
		throw new Error("Invalid dependencies.lock");
	return lock;
}

function definitions(): Map<string, DependencySpec> {
	const data = parse(
		fs.readFileSync(path.join(dependencies, "dependencies.toml"), "utf8"),
	);
	const result = new Map<string, DependencySpec>();
	for (const [group, entries] of Object.entries(data)) {
		if (!entries || typeof entries !== "object" || Array.isArray(entries))
			throw new Error(`Invalid dependency group: ${group}`);
		for (const [name, spec] of Object.entries(entries)) {
			if (!spec || typeof spec !== "object" || Array.isArray(spec))
				throw new Error(`Invalid dependency: ${group}.${name}`);
			result.set(`${group}.${name}`, spec as DependencySpec);
		}
	}
	return result;
}

export function matchAsset(pattern: string, name: string) {
	const escaped = pattern
		.split("*")
		.map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
		.join(".*");
	return new RegExp(`^${escaped}$`).test(name);
}

async function request(url: string, accept: string): Promise<Response> {
	for (let attempt = 0; attempt < 3; attempt++) {
		let response: Response;
		try {
			response = await fetch(url, {
				headers: {
					"User-Agent": "workspace-dependency-loader",
					Accept: accept,
				},
				signal: AbortSignal.timeout(120000),
			});
		} catch (error) {
			if (attempt === 2)
				throw new Error(`Unable to download dependency: ${url}`, {
					cause: error,
				});
			await new Promise((resolve) => setTimeout(resolve, 500 * (attempt + 1)));
			continue;
		}
		if (response.ok) return response;
		if ((response.status === 429 || response.status >= 500) && attempt < 2) {
			await response.body?.cancel();
			await new Promise((resolve) => setTimeout(resolve, 500 * (attempt + 1)));
			continue;
		}
		throw new Error(`Dependency request failed (${response.status}): ${url}`);
	}
	throw new Error(`Unable to download dependency: ${url}`);
}

function releaseAsset(
	spec: DependencySpec,
	locked: LockedDependency,
): { asset: ReleaseAsset; version: string } {
	const match =
		typeof spec.source === "string" &&
		spec.source.match(/^github\.com\/([\w.-]+)\/([\w.-]+)$/);
	if (!match)
		throw new Error(`Unsupported dependency source: ${String(spec.source)}`);
	const entry = locked.platforms?.[platform];
	if (
		!entry ||
		typeof entry.url !== "string" ||
		typeof entry.digest !== "string" ||
		!/^sha256:[a-f0-9]{64}$/i.test(entry.digest)
	)
		throw new Error(
			`No valid locked release asset for ${platform}: ${spec.source}`,
		);
	if (spec.version !== undefined && String(spec.version) !== locked.version)
		throw new Error(
			`Manifest version does not match dependencies.lock: ${spec.source}`,
		);
	if (
		spec.assets?.[platform] &&
		!matchAsset(spec.assets[platform], entry.asset)
	)
		throw new Error(`Locked asset does not match manifest: ${entry.asset}`);
	if (entry.executable && spec.executables?.[platform] !== entry.executable)
		throw new Error(
			`Locked executable does not match manifest: ${entry.executable}`,
		);
	const url = new URL(entry.url);
	if (
		url.protocol !== "https:" ||
		url.hostname !== "github.com" ||
		!url.pathname.includes(`/${match[1]}/${match[2]}/releases/download/`)
	)
		throw new Error(`Unexpected locked release URL: ${entry.url}`);
	const asset: ReleaseAsset = {
		name: entry.asset,
		digest: entry.digest,
		browser_download_url: entry.url,
	};
	return { asset, version: locked.version };
}

function findExecutable(directory: string, name: string) {
	if (typeof name !== "string" || !name || name !== path.basename(name))
		throw new Error("Executable must be a filename");
	const matches: string[] = [];
	function visit(parent: string) {
		for (const entry of fs.readdirSync(parent, { withFileTypes: true })) {
			const target = path.join(parent, entry.name);
			if (entry.isSymbolicLink())
				throw new Error(`Unexpected symlink: ${target}`);
			if (entry.isDirectory()) visit(target);
			else if (entry.isFile() && entry.name === name) matches.push(target);
		}
	}
	visit(directory);
	if (matches.length !== 1)
		throw new Error(
			`Expected one executable named ${name}; found ${matches.length}`,
		);
	return matches[0];
}

function setup(stage: string, executable: string, spec: DependencySpec) {
	if (spec.setup === undefined) return;
	if (
		!Array.isArray(spec.setup) ||
		!spec.setup.every((value) => typeof value === "string")
	)
		throw new Error("Dependency setup must be an array of arguments");
	const home = path.join(stage, ".dependency-home");
	fs.mkdirSync(home);
	const result = spawnSync(executable, spec.setup, {
		cwd: stage,
		env: { ...process.env, HOME: home, USERPROFILE: home },
		encoding: "utf8",
		windowsHide: true,
		timeout: 120000,
	});
	if (result.error || result.status !== 0)
		throw new Error(
			`Dependency setup failed: ${result.error?.message || result.stderr || result.stdout || result.status}`,
		);
	if (spec.setupAliases) {
		const generated = JSON.parse(
			fs.readFileSync(path.join(stage, ".luaurc"), "utf8"),
		);
		for (const [alias, relative] of Object.entries(spec.setupAliases)) {
			const sourceAlias = generated.aliases?.[alias];
			if (
				typeof sourceAlias !== "string" ||
				!sourceAlias.startsWith("~/") ||
				typeof relative !== "string" ||
				path.isAbsolute(relative)
			)
				throw new Error(`Invalid generated setup alias: ${alias}`);
			const source = path.resolve(home, sourceAlias.slice(2));
			const target = path.resolve(stage, relative);
			if (!within(home, source) || (target !== stage && !within(stage, target)))
				throw new Error(`Unsafe generated setup alias: ${alias}`);
			fs.cpSync(source, target, {
				recursive: true,
				force: true,
				errorOnExist: false,
			});
		}
		fs.unlinkSync(path.join(stage, ".luaurc"));
	}
	fs.rmSync(home, { recursive: true, force: true });
}

async function ensure(
	name: string,
	spec: DependencySpec,
): Promise<string | undefined> {
	if (!spec.source) {
		const local = path.resolve(dependencies, spec.path || "");
		if (!within(dependencies, local) || !fs.statSync(local).isDirectory())
			throw new Error(`Invalid local dependency ${name}`);
		return undefined;
	}
	if (typeof spec.path !== "string")
		throw new Error(`Missing managed path: ${name}`);
	const target = managedPath(spec.path);
	const locked = readLock().dependencies[name];
	if (!locked)
		throw new Error(`Dependency is not pinned in dependencies.lock: ${name}`);
	if (spec.version !== undefined && String(spec.version) !== locked.version)
		throw new Error(
			`Dependency version changed: ${name}; run --update-lock first`,
		);
	const marker = path.join(target, ".dependency.json");
	const configuration = crypto
		.createHash("sha256")
		.update(
			JSON.stringify({
				source: spec.source,
				package: spec.package,
				lock: locked,
				platform,
				setup: spec.setup,
				setupAliases: spec.setupAliases,
				binaryPath: spec.binaryPath,
				typesPath: spec.typesPath,
			}),
		)
		.digest("hex");
	if (fs.existsSync(target) && fs.readdirSync(target).length === 0)
		fs.rmdirSync(target);
	if (fs.existsSync(target)) {
		if (!fs.existsSync(marker)) {
			if (
				spec.source !== "npm" ||
				!locked.npm ||
				typeof spec.package !== "string"
			)
				throw new Error(
					`Managed dependency directory is not owned by the loader: ${target}`,
				);
			const metadata = JSON.parse(
				fs.readFileSync(path.join(target, "package.json"), "utf8"),
			);
			if (metadata.name !== spec.package || metadata.version !== locked.version)
				throw new Error(`Unrecognized incomplete npm package: ${spec.package}`);
			await installNpmDependencies(spec.package, locked, target);
			fs.writeFileSync(
				marker,
				JSON.stringify(
					{ source: spec.source, version: locked.version, configuration },
					null,
					2,
				),
			);
			return undefined;
		}
		const state = JSON.parse(fs.readFileSync(marker, "utf8"));
		const executable = state.executable
			? path.resolve(generated, state.executable)
			: undefined;
		if (
			typeof state.configuration !== "string" ||
			!/^[a-f0-9]{64}$/.test(state.configuration)
		)
			throw new Error(`Unrecognized dependency installation marker: ${name}`);
		if (
			state.source === spec.source &&
			state.configuration === configuration &&
			(!executable ||
				(within(generated, executable) && fs.existsSync(executable)))
		)
			return executable;
		// This directory has a loader marker and is confined to generated output.
		// Rebuild stale installations when the manifest or lock changes.
		fs.rmSync(target, { recursive: true, force: true });
	}
	if (spec.source === "npm") {
		const packageName = spec.package;
		const npm = locked.npm;
		if (
			typeof packageName !== "string" ||
			!npm ||
			!/^https:\/\/registry\.npmjs\.org\//.test(npm.url) ||
			!/^sha512-[A-Za-z0-9+/]+=*$/.test(npm.integrity)
		)
			throw new Error(`Invalid npm lock entry: ${name}`);
		await installNpm(packageName, spec, locked, target);
		fs.writeFileSync(
			marker,
			JSON.stringify(
				{ source: spec.source, version: locked.version, configuration },
				null,
				2,
			),
		);
		return undefined;
	}
	const executableName = spec.executables?.[platform];
	if (typeof executableName !== "string")
		throw new Error(`No executable configured for ${platform}: ${name}`);
	const { asset, version } = releaseAsset(spec, locked);
	const expectedDigest = asset.digest;
	if (!expectedDigest)
		throw new Error(`Release asset has no SHA-256 digest: ${asset.name}`);
	const response = await request(
		asset.browser_download_url,
		"application/octet-stream",
	);
	if (Number(response.headers.get("content-length")) > 512 * 1024 * 1024)
		throw new Error(`Dependency archive is too large: ${name}`);
	const bytes = Buffer.from(await response.arrayBuffer());
	const digest = crypto.createHash("sha256").update(bytes).digest("hex");
	if (`sha256:${digest}`.toLowerCase() !== expectedDigest.toLowerCase())
		throw new Error(`Checksum mismatch: ${asset.name}`);
	fs.mkdirSync(path.dirname(target), { recursive: true });
	const stage = fs.mkdtempSync(path.join(os.tmpdir(), "workspace-dependency-"));
	const publication = path.join(
		path.dirname(target),
		`.${path.basename(target)}-${crypto.randomUUID()}`,
	);
	try {
		extract(stage, asset.name, bytes, executableName);
		const executable = findExecutable(stage, executableName);
		if (process.platform !== "win32") fs.chmodSync(executable, 0o755);
		setup(stage, executable, spec);
		const relative = path.relative(stage, executable);
		// Copy to a new sibling, then publish the complete package atomically.
		// In particular, Electron's fs.cp cannot copy into a pre-created root
		// with errorOnExist enabled, even when that root is empty.
		fs.cpSync(stage, publication, {
			recursive: true,
			force: false,
			errorOnExist: true,
		});
		let binary = path.join(target, relative);
		if (spec.binaryPath) {
			const binaryRoot = managedPath(spec.binaryPath);
			fs.mkdirSync(binaryRoot, { recursive: true });
			binary = path.join(binaryRoot, executableName);
			fs.copyFileSync(executable, binary);
		}
		if (spec.typesPath)
			fs.cpSync(stage, managedPath(spec.typesPath), {
				recursive: true,
				force: true,
				filter: (source) =>
					fs.statSync(source).isDirectory() ||
					source.endsWith(".luau") ||
					path.basename(source) === ".luaurc",
			});
		fs.writeFileSync(
			path.join(publication, ".dependency.json"),
			JSON.stringify(
				{
					source: spec.source,
					version,
					asset: asset.name,
					digest: expectedDigest,
					executable: path.relative(generated, binary),
					configuration,
				},
				null,
				2,
			),
		);
		fs.renameSync(publication, target);
		return binary;
	} finally {
		if (within(generated, publication))
			fs.rmSync(publication, { recursive: true, force: true });
		try {
			removeStage(stage);
		} catch {
			/* The operating system can clean temporary staging files. */
		}
	}
}

async function installNpm(
	name: string,
	spec: DependencySpec,
	locked: LockedDependency,
	target: string,
): Promise<void> {
	const npm = locked.npm;
	if (
		!npm ||
		!/^https:\/\/registry\.npmjs\.org\//.test(npm.url) ||
		!/^sha512-[A-Za-z0-9+/]+=*$/.test(npm.integrity)
	)
		throw new Error(`Invalid npm lock entry: ${name}`);
	if (fs.existsSync(target)) {
		const metadata = JSON.parse(
			fs.readFileSync(path.join(target, "package.json"), "utf8"),
		);
		if (metadata.name !== name || metadata.version !== locked.version)
			throw new Error(`npm package identity mismatch: ${name}`);
		await installNpmDependencies(name, locked, target);
		return;
	}
	const response = await request(npm.url, "application/octet-stream");
	const bytes = Buffer.from(await response.arrayBuffer());
	if (
		`sha512-${crypto.createHash("sha512").update(bytes).digest("base64")}` !==
		npm.integrity
	)
		throw new Error(`npm integrity mismatch: ${name}`);
	const stage = fs.mkdtempSync(path.join(os.tmpdir(), "workspace-dependency-"));
	try {
		extract(stage, "package.tgz", bytes, "");
		const roots = fs.readdirSync(stage, { withFileTypes: true });
		if (roots.length !== 1 || !roots[0].isDirectory())
			throw new Error(`Invalid npm package archive: ${name}`);
		const packageRoot = path.join(stage, roots[0].name);
		const metadata = JSON.parse(
			fs.readFileSync(path.join(packageRoot, "package.json"), "utf8"),
		);
		if (metadata.name !== name || metadata.version !== locked.version)
			throw new Error(`npm package identity mismatch: ${name}`);
		await installNpmDependencies(name, locked, packageRoot);
		fs.mkdirSync(path.dirname(target), { recursive: true });
		fs.cpSync(packageRoot, target, {
			recursive: true,
			force: false,
			errorOnExist: true,
		});
	} finally {
		removeStage(stage);
	}
}

async function installNpmDependencies(
	name: string,
	locked: LockedDependency,
	packageRoot: string,
): Promise<void> {
	for (const [dependencyName, dependencyVersion] of Object.entries(
		locked.npm?.dependencies || {},
	)) {
		const dependencyLock = readLock().dependencies[`npm:${dependencyName}`];
		if (!dependencyLock || dependencyLock.version !== dependencyVersion)
			throw new Error(
				`Missing exact npm dependency lock for ${name} -> ${dependencyName}@${dependencyVersion}`,
			);
		const dependencyTarget = path.join(
			packageRoot,
			"node_modules",
			...dependencyName.split("/"),
		);
		await installNpm(
			dependencyName,
			{ source: "npm", package: dependencyName },
			dependencyLock,
			dependencyTarget,
		);
	}
}

function generateBridges() {
	const luaurcPath = path.join(root, ".vscode", "config", "luau", ".luaurc");
	if (fs.existsSync(luaurcPath)) {
		const source = fs.readFileSync(luaurcPath, "utf8");
		let json = "";
		let quoted = false;
		let escaped = false;
		for (let index = 0; index < source.length; index++) {
			const character = source[index];
			if (quoted) {
				json += character;
				if (escaped) escaped = false;
				else if (character === "\\") escaped = true;
				else if (character === '"') quoted = false;
			} else if (character === '"') {
				quoted = true;
				json += character;
			} else if (character === "/" && source[index + 1] === "/") {
				while (index < source.length && source[index] !== "\n") index++;
				json += "\n";
			} else json += character;
		}
		const luaurc = JSON.parse(json.replace(/,\s*([}\]])/g, "$1"));
		if (luaurc.aliases && typeof luaurc.aliases === "object")
			luaurc.aliases.workspace = ".";
		fs.writeFileSync(
			path.join(root, ".luaurc"),
			`${JSON.stringify(luaurc, null, 2)}\n`,
		);
	}
	const tsconfig = path.join(
		root,
		".vscode",
		"config",
		"typescript",
		"tsconfig.json",
	);
	if (fs.existsSync(tsconfig))
		fs.writeFileSync(
			path.join(root, "tsconfig.json"),
			`${JSON.stringify({ extends: "./.vscode/config/typescript/tsconfig.json" }, null, 2)}\n`,
		);
}

function reportProgress(
	message: string,
	completed: number,
	total: number,
	detail?: string,
): void {
	if (process.env.VSCODE_WORKSPACE_SETUP !== "1") return;
	process.stdout.write(
		`::workspace-setup::${JSON.stringify({ message, completed, total, detail })}\n`,
	);
}

async function loadDependencies(
	specs: Map<string, DependencySpec>,
): Promise<void> {
	let completed = 0;
	for (const [name, spec] of specs) {
		reportProgress("Loading dependencies", completed, specs.size, name);
		await ensure(name, spec);
		completed++;
	}
	generateBridges();
	reportProgress("Dependencies ready", completed, specs.size);
}

export async function main(args: string[]): Promise<void> {
	const specs = definitions();
	if (args.length === 1 && args[0] === "--update-lock") {
		await updateLock(specs, lockPath);
		return;
	}
	readLock();
	if (args[0] === "--exec") {
		const name = args[1];
		const spec = specs.get(name);
		if (!spec) throw new Error(`Unknown dependency: ${name}`);
		await loadDependencies(specs);
		const executable = await ensure(name, spec);
		if (!executable)
			throw new Error(`Local dependency has no executable: ${name}`);
		const result = spawnSync(executable, args.slice(2), {
			cwd: process.cwd(),
			env: process.env,
			stdio: "inherit",
			windowsHide: true,
		});
		if (result.error) throw result.error;
		process.exitCode = result.status ?? 1;
		return;
	}
	if (args.length)
		throw new Error(
			"Usage: dependency-loader [--update-lock | --exec group.name [arguments...]]",
		);
	await loadDependencies(specs);
}

if (
	process.argv[1] &&
	path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
	main(process.argv.slice(2)).catch((error: unknown) => {
		console.error(error instanceof Error ? error.message : error);
		process.exitCode = 1;
	});
