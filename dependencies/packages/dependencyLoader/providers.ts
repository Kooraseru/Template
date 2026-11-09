import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { args, contained, record, relativePath, type Installation, type Provider, type ProviderRequest } from "./contract.ts";
import { githubRelease } from "./githubRelease.ts";
import { workspaceNpm } from "./workspaceNpm.ts";

const local: Provider = {
	resolve() { return null; },
	install({ workspace, options }) {
		const relative = "dependencies/" + relativePath(options.path);
		const directory = contained(workspace, relative);
		if (!fs.statSync(directory, { throwIfNoEntry: false })?.isDirectory()) {
			throw new Error("Local dependency directory does not exist: " + relative);
		}
		return { outputs: [], exports: { source: { root: "workspace", path: relative } } };
	},
};

const builtins = new Map<string, Provider>([
	["local", local],
	["github-release", githubRelease],
	["npm", workspaceNpm],
]);

export function commandInvocation(command: string[]): [string, string[]] {
	const [program, ...arguments_] = command;
	return [program === "node" ? process.execPath : program, arguments_];
}

export function providerFrom(value: unknown): Provider {
	const registration = record(value, "Invalid provider registration");
	if (Object.keys(registration).some(key => !["builtin", "command", "inputs"].includes(key))
		|| Object.hasOwn(registration, "builtin") === Object.hasOwn(registration, "command")) {
		throw new Error("A provider needs one builtin or command");
	}
	if (typeof registration.builtin === "string") {
		const provider = builtins.get(registration.builtin);
		if (!provider) throw new Error("Unknown built-in provider: " + registration.builtin);
		return provider;
	}
	const command = args(registration.command, "provider command");
	function invoke(request: ProviderRequest) {
		const [program, arguments_] = commandInvocation(command);
		const result = spawnSync(program, arguments_, {
			cwd: request.workspace, input: JSON.stringify(request) + "\n", encoding: "utf8",
			windowsHide: true, timeout: 120_000, maxBuffer: 16 * 1024 * 1024,
			env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
		});
		if (result.stderr) process.stderr.write(result.stderr);
		if (result.error) throw result.error;
		if (result.status !== 0) throw new Error("Provider command exited with status " + result.status);
		return record(JSON.parse(result.stdout), "Expected a JSON response from provider");
	}
	return {
		resolve(request) {
			const response = invoke(request);
			if (!Object.hasOwn(response, "resolution")) throw new Error("Provider response is missing resolution");
			return response.resolution;
		},
		install(request) { return invoke(request) as unknown as Installation; },
	};
}

export function execute(executable: string, interpreter: string[] | undefined, forwarded: string[]) {
	const [program, arguments_] = interpreter ? commandInvocation([...interpreter, executable]) : [executable, []];
	const result = spawnSync(program, [...arguments_, ...forwarded], {
		cwd: path.resolve(process.cwd()), stdio: "inherit", windowsHide: true,
		env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
	});
	if (result.error) throw result.error;
	return result.status ?? 1;
}
