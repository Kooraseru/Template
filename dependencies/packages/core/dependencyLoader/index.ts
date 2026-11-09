import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { contained } from "./contract.ts";
import { load } from "./loader.ts";
import { execute } from "./providers.ts";
import { withStage } from "./publication.ts";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../..");

function generateBridges(root: string) {
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

export async function main(args: string[], workspace = root): Promise<number> {
	const only = args[0] === "--only" ? args[1]?.split(",") : undefined;
	if (args[0] === "--only") {
		if (!only?.every(Boolean) || args[2] !== "--exec") {
			throw new Error("Usage: dependency-loader --only ID[,ID...] --exec ID [arguments...]");
		}
		args = args.slice(2);
	}
	const update = args.length === 1 && args[0] === "--update-lock";
	const requested = args[0] === "--exec" ? args[1] : undefined;
	if (args.length && !update && !requested) {
		throw new Error("Usage: dependency-loader [--update-lock | --exec ID [arguments...]]");
	}
	const generated = contained(workspace, "build/dependencies");
	const executable = await withStage(generated, async stage => {
		const selected = await load(workspace, generated, stage, update, reportProgress, requested, only);
		if (!update) generateBridges(workspace);
		return selected;
	});
	return executable ? execute(executable.path, executable.interpreter, args.slice(2)) : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	main(process.argv.slice(2)).then(status => { process.exitCode = status; }).catch((error: unknown) => {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	});
}
