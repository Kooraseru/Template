import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { json, readJson, record, relativePath, type Export, type Provider, type RecordValue } from "./contract.ts";

function npm(cwd: string, args: string[]) {
	let program = "npm";
	if (process.platform === "win32") {
		const locations = [path.dirname(process.execPath), ...(process.env.PATH || "").split(path.delimiter)];
		const cli = locations.filter(Boolean).map(directory => path.join(directory, "node_modules/npm/bin/npm-cli.js"))
			.find(candidate => fs.existsSync(candidate));
		if (!cli) throw new Error("Cannot locate npm-cli.js in the Node installation or on PATH");
		program = process.execPath;
		args = [cli, ...args];
	}
	const result = spawnSync(program, [...args, "--ignore-scripts", "--no-audit", "--no-fund"], {
		cwd, stdio: ["ignore", 2, 2], windowsHide: true, timeout: 120_000,
		env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
	});
	if (result.error) throw result.error;
	if (result.status !== 0) throw new Error("npm exited with status " + result.status);
}

function project(stage: string, options: RecordValue, lock: unknown) {
	const directory = path.join(stage, "project");
	fs.mkdirSync(directory);
	const manifest = record(options.manifest, "npm provider requires a manifest");
	fs.writeFileSync(path.join(directory, "package.json"), json(manifest));
	const lockFile = path.join(directory, "package-lock.json");
	if (lock !== undefined) fs.writeFileSync(lockFile, json(record(lock, "Invalid npm lock")));
	return { directory, manifest, lockFile };
}

export const workspaceNpm: Provider = {
	resolve({ stage, options, previous }) {
		const { directory, lockFile } = project(stage, options, previous);
		npm(directory, ["install", "--package-lock-only"]);
		return readJson(lockFile);
	},
	install({ stage, options, resolution }) {
		const { directory, manifest } = project(stage, options, record(resolution, "Missing locked npm resolution"));
		const target = relativePath(options.path ?? "npm");
		npm(directory, ["ci"]);
		fs.mkdirSync(path.join(directory, "node_modules"), { recursive: true });
		const exports: Record<string, Export> = {
			project: { root: "managed", path: target },
			manifest: { root: "managed", path: target + "/package.json" },
			lock: { root: "managed", path: target + "/package-lock.json" },
			modules: { root: "managed", path: target + "/node_modules" },
		};
		for (const name of Object.keys(record(manifest.dependencies ?? {}, "Invalid npm dependencies"))) {
			exports["package:" + name] = { root: "managed", path: relativePath(target + "/node_modules/" + name + "/package.json") };
		}
		return { outputs: [{ from: "project", to: target }], exports };
	},
};
