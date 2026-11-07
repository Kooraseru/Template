import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

export type DependencySpec = {
	source?: string;
	package?: string;
	version?: string | number;
	assets?: Record<string, string>;
	executables?: Record<string, string>;
};

type LockedPackage = {
	version: string;
	platforms?: Record<string, { asset: string; url: string; digest: string }>;
	npm?: {
		url: string;
		integrity: string;
		dependencies: Record<string, string>;
	};
};

type LockFile = { version: 1; dependencies: Record<string, LockedPackage> };
type ReleaseAsset = {
	name: string;
	digest?: string;
	browser_download_url: string;
};
type Release = {
	tag_name: string;
	draft: boolean;
	prerelease: boolean;
	assets: ReleaseAsset[];
};
type NpmVersion = {
	version: string;
	"dist.tarball": string;
	"dist.integrity": string;
	dependencies?: Record<string, string>;
};

function record(value: unknown, message: string): Record<string, unknown> {
	if (!value || typeof value !== "object" || Array.isArray(value))
		throw new Error(message);
	return value as Record<string, unknown>;
}

function assetMatches(pattern: string, name: string): boolean {
	const escaped = pattern
		.split("*")
		.map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
		.join(".*");
	return new RegExp(`^${escaped}$`).test(name);
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

async function githubLock(spec: DependencySpec): Promise<LockedPackage> {
	const match =
		typeof spec.source === "string" &&
		spec.source.match(/^github\.com\/([\w.-]+)\/([\w.-]+)$/);
	if (!match)
		throw new Error(
			`Unsupported GitHub dependency source: ${String(spec.source)}`,
		);
	const releaseUrl =
		spec.version === undefined
			? `https://api.github.com/repos/${match[1]}/${match[2]}/releases/latest`
			: `https://api.github.com/repos/${match[1]}/${match[2]}/releases/tags/${encodeURIComponent(String(spec.version))}`;
	const raw = record(
		await fetchJson(releaseUrl, "application/vnd.github+json"),
		`Invalid release metadata: ${releaseUrl}`,
	);
	const release = raw as unknown as Release;
	if (
		release.draft ||
		(spec.version === undefined && release.prerelease) ||
		typeof release.tag_name !== "string" ||
		!Array.isArray(release.assets)
	)
		throw new Error(`Expected a published release: ${releaseUrl}`);
	if (spec.version !== undefined && release.tag_name !== String(spec.version))
		throw new Error(
			`Manifest version ${String(spec.version)} resolved to unexpected tag ${release.tag_name}`,
		);
	const platforms: NonNullable<LockedPackage["platforms"]> = {};
	for (const [platform, pattern] of Object.entries(spec.assets || {})) {
		const candidates = release.assets.filter((asset) =>
			assetMatches(pattern, asset.name),
		);
		if (candidates.length !== 1)
			throw new Error(
				`Expected one release asset for ${platform} (${pattern}); found ${candidates.length}`,
			);
		const asset = candidates[0];
		if (
			typeof asset.digest !== "string" ||
			!/^sha256:[a-f0-9]{64}$/i.test(asset.digest)
		)
			throw new Error(`Release asset has no SHA-256 digest: ${asset.name}`);
		const url = new URL(asset.browser_download_url);
		if (
			url.protocol !== "https:" ||
			url.hostname !== "github.com" ||
			!url.pathname.includes(`/${match[1]}/${match[2]}/releases/download/`)
		)
			throw new Error(`Unexpected release asset URL: ${asset.name}`);
		platforms[platform] = {
			asset: asset.name,
			url: asset.browser_download_url,
			digest: asset.digest,
		};
	}
	if (Object.keys(platforms).length === 0)
		throw new Error(`No platform assets configured for ${spec.source}`);
	return { version: release.tag_name, platforms };
}

function npmView(packageName: string, range: string): NpmVersion {
	if (
		!/^(@[a-z0-9._-]+\/)?[a-z0-9._-]+$/i.test(packageName) ||
		!range ||
		range.length > 128 ||
		/[\r\n\0]/.test(range)
	)
		throw new Error(`Invalid npm package selector: ${packageName}@${range}`);
	const args = [
		"view",
		`${packageName}@${range}`,
		"version",
		"dist.tarball",
		"dist.integrity",
		"dependencies",
		"--json",
	];
	let command = "npm";
	let commandArgs = args;
	if (process.platform === "win32") {
		command = process.execPath;
		commandArgs = [
			path.join(
				path.dirname(process.execPath),
				"node_modules",
				"npm",
				"bin",
				"npm-cli.js",
			),
			...args,
		];
	}
	const result = spawnSync(command, commandArgs, {
		encoding: "utf8",
		timeout: 120000,
		windowsHide: true,
		maxBuffer: 8 * 1024 * 1024,
	});
	if (result.error || result.status !== 0)
		throw new Error(
			`npm view failed for ${packageName}@${range}: ${result.error?.message || result.stderr || result.status}`,
		);
	const parsed: unknown = JSON.parse(result.stdout);
	const versions = Array.isArray(parsed) ? parsed : [parsed];
	const selected = record(
		versions[versions.length - 1],
		`No npm version matched ${packageName}@${range}`,
	);
	if (
		typeof selected.version !== "string" ||
		typeof selected["dist.tarball"] !== "string" ||
		typeof selected["dist.integrity"] !== "string"
	)
		throw new Error(`Incomplete npm metadata for ${packageName}@${range}`);
	const tarball = new URL(selected["dist.tarball"]);
	if (
		tarball.protocol !== "https:" ||
		tarball.hostname !== "registry.npmjs.org" ||
		!/^sha512-[A-Za-z0-9+/]+=*$/.test(selected["dist.integrity"])
	)
		throw new Error(
			`Invalid npm distribution metadata for ${packageName}@${range}`,
		);
	const dependencies =
		selected.dependencies === undefined
			? undefined
			: record(
					selected.dependencies,
					`Invalid npm dependency list: ${packageName}@${selected.version}`,
				);
	const dependencyMap: Record<string, string> = {};
	if (dependencies) {
		for (const [name, value] of Object.entries(dependencies)) {
			if (typeof value !== "string")
				throw new Error(`Invalid npm dependency range: ${name}`);
			dependencyMap[name] = value;
		}
	}
	return {
		version: selected.version,
		"dist.tarball": selected["dist.tarball"],
		"dist.integrity": selected["dist.integrity"],
		dependencies: dependencyMap,
	};
}

function npmLockEntry(
	info: NpmVersion,
	dependencies: Record<string, string>,
): LockedPackage {
	return {
		version: info.version,
		npm: {
			url: info["dist.tarball"],
			integrity: info["dist.integrity"],
			dependencies,
		},
	};
}

function resolveNpmTree(
	name: string,
	range: string,
	output: Record<string, LockedPackage>,
	resolving: Set<string>,
): string {
	const info = npmView(name, range);
	const lockKey = `npm:${name}`;
	const existing = output[lockKey];
	if (existing && existing.version !== info.version)
		throw new Error(
			`npm dependency ${name} resolved to conflicting versions ${existing.version} and ${info.version}`,
		);
	if (resolving.has(lockKey)) return info.version;
	resolving.add(lockKey);
	const exactDependencies: Record<string, string> = {};
	for (const [dependencyName, dependencyRange] of Object.entries(
		info.dependencies || {},
	)) {
		exactDependencies[dependencyName] = resolveNpmTree(
			dependencyName,
			dependencyRange,
			output,
			resolving,
		);
	}
	resolving.delete(lockKey);
	output[lockKey] = npmLockEntry(info, exactDependencies);
	return info.version;
}

export async function updateLock(
	specs: Map<string, DependencySpec>,
	lockPath: string,
): Promise<void> {
	const dependencies: Record<string, LockedPackage> = {};
	for (const [name, spec] of specs) {
		if (!spec.source) continue;
		if (spec.source === "npm") {
			if (typeof spec.package !== "string" || spec.version === undefined)
				throw new Error(`npm dependency requires package and version: ${name}`);
			const info = npmView(spec.package, String(spec.version));
			const exactDependencies: Record<string, string> = {};
			for (const [dependencyName, dependencyRange] of Object.entries(
				info.dependencies || {},
			)) {
				exactDependencies[dependencyName] = resolveNpmTree(
					dependencyName,
					dependencyRange,
					dependencies,
					new Set(),
				);
			}
			dependencies[name] = npmLockEntry(info, exactDependencies);
		} else {
			dependencies[name] = await githubLock(spec);
		}
	}
	const lock: LockFile = { version: 1, dependencies };
	fs.writeFileSync(lockPath, `${JSON.stringify(lock, null, 2)}\n`);
}
