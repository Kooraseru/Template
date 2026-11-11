import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { extract } from "./archive.ts";
import { record, relativePath, text, within, type Provider, type RecordValue } from "./contract.ts";

type DependencySpec = { setup?: string[]; setupAliases?: Record<string, string> };
function matchAsset(pattern: string, name: string) {
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

async function fetchJson(url: string, accept: string): Promise<unknown> {
	const response = await fetch(url, {
		headers: { "User-Agent": "workspace-dependency-loader", Accept: accept },
		signal: AbortSignal.timeout(120000),
	});
	if (!response.ok)
		throw new Error(`Lock update request failed (${response.status}): ${url}`);
	return response.json();
}


type Asset = { asset: string; url: string; digest: string };
type Resolution = { version: string; platforms: Record<string, Asset> };

function releaseOptions(options: RecordValue) {
	const repository = text(options.repository, "GitHub repository");
	if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error("Invalid GitHub repository: " + repository);
	const version = options.version === undefined ? undefined : text(options.version, "release version");
	const platforms = record(options.platforms, "Expected release platforms");
	if (!Object.keys(platforms).length) throw new Error("Expected at least one release platform");
	const packagePath = relativePath(options.packagePath);
	const binaryPath = options.binaryPath === undefined ? undefined : relativePath(options.binaryPath);
	const typesPath = options.typesPath === undefined ? undefined : relativePath(options.typesPath);
	return { repository, version, platforms, packagePath, binaryPath, typesPath };
}

function platformOptions(value: unknown, key: string) {
	const config = record(value, "No release asset configured for " + key);
	const executable = text(config.executable, "release executable");
	if (relativePath(executable).includes("/")) throw new Error("Expected an executable filename: " + executable);
	return { pattern: text(config.asset, "release asset pattern"), executable };
}

function checkedAsset(value: unknown, repository: string, pattern: string): Asset {
	const entry = record(value, "Missing locked release asset for " + repository);
	const asset = text(entry.asset, "locked asset filename");
	const digest = text(entry.digest, "locked asset digest");
	const url = new URL(text(entry.url, "locked asset URL"));
	if (!matchAsset(pattern, asset) || !/^sha256:[a-f0-9]{64}$/i.test(digest)) {
		throw new Error("Locked asset does not match the release declaration: " + asset);
	}
	if (url.protocol !== "https:" || url.hostname !== "github.com" ||
		!url.pathname.startsWith("/" + repository + "/releases/download/")) {
		throw new Error("Unexpected locked release URL: " + url.href);
	}
	return { asset, digest, url: url.href };
}

export const githubRelease: Provider = {
	async resolve({ options, previous }) {
		const spec = releaseOptions(options);
		const old = previous as Resolution | undefined;
		const matches = Object.entries(spec.platforms);
		if (spec.version && old?.version === spec.version && Object.keys(old.platforms || {}).length === matches.length) {
			try {
				for (const [key, value] of matches) {
					checkedAsset(old.platforms[key], spec.repository, platformOptions(value, key).pattern);
				}
				return old;
			} catch { /* Resolve when the requested platform assets change. */ }
		}
		const releaseUrl = "https://api.github.com/repos/" + spec.repository + "/releases/"
			+ (spec.version ? "tags/" + encodeURIComponent(spec.version) : "latest");
		const release = record(await fetchJson(releaseUrl, "application/vnd.github+json"), "Invalid release metadata");
		const version = text(release.tag_name, "release tag");
		if (release.draft || (!spec.version && release.prerelease) || (spec.version && version !== spec.version) || !Array.isArray(release.assets)) {
			throw new Error("Expected a published release: " + releaseUrl);
		}
		const platforms: Record<string, Asset> = {};
		for (const [key, value] of matches) {
			const { pattern } = platformOptions(value, key);
			const candidates = release.assets.filter(asset => typeof asset?.name === "string" && matchAsset(pattern, asset.name));
			if (candidates.length !== 1) throw new Error("Expected one release asset for " + key + " matching " + pattern);
			const asset = candidates[0];
			platforms[key] = checkedAsset({ asset: asset.name, url: asset.browser_download_url, digest: asset.digest }, spec.repository, pattern);
		}
		return { version, platforms };
	},
	async install({ options, resolution, stage, platform, arch }) {
		const spec = releaseOptions(options);
		const locked = record(resolution, "Invalid GitHub release resolution");
		if (spec.version && locked.version !== spec.version) throw new Error("Release version does not match the lock");
		const key = platform + "-" + arch;
		const { pattern, executable: filename } = platformOptions(spec.platforms[key], key);
		const asset = checkedAsset(record(locked.platforms, "Missing locked platforms")[key], spec.repository, pattern);
		const response = await request(asset.url, "application/octet-stream");
		if (Number(response.headers.get("content-length")) > 512 * 1024 * 1024) throw new Error("Release archive is too large: " + asset.asset);
		const bytes = Buffer.from(await response.arrayBuffer());
		const hash = crypto.createHash("sha256").update(bytes).digest("hex");
		if ("sha256:" + hash !== asset.digest.toLowerCase()) throw new Error("Checksum mismatch: " + asset.asset);

		const packageDir = path.join(stage, "package");
		fs.mkdirSync(packageDir);
		extract(packageDir, asset.asset, bytes, filename);
		const executable = findExecutable(packageDir, filename);
		if (platform !== "win32") fs.chmodSync(executable, 0o755);
		setup(packageDir, executable, options as DependencySpec);
		const outputs = [{ from: "package", to: spec.packagePath }];
		let executablePath = spec.packagePath + "/" + path.relative(packageDir, executable).split(path.sep).join("/");
		if (spec.binaryPath) {
			const bin = path.join(stage, "bin");
			fs.mkdirSync(bin);
			fs.copyFileSync(executable, path.join(bin, filename));
			if (platform !== "win32") fs.chmodSync(path.join(bin, filename), 0o755);
			outputs.push({ from: "bin", to: spec.binaryPath });
			executablePath = spec.binaryPath + "/" + filename;
		}
		if (spec.typesPath) {
			fs.cpSync(packageDir, path.join(stage, "types"), {
				recursive: true,
				filter: source => fs.statSync(source).isDirectory() || source.endsWith(".luau") || path.basename(source) === ".luaurc",
			});
			outputs.push({ from: "types", to: spec.typesPath });
		}
		return {
			outputs,
			exports: { executable: { root: "managed", path: executablePath }, package: { root: "managed", path: spec.packagePath } },
			executable: { export: "executable" },
		};
	},
};
