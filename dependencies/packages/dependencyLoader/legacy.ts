import fs from "node:fs";
import { contained, readJson } from "./contract.ts";

// Recognize the previous loader's ownership markers on upgrade. Unmarked directories
// are left alone, including installations from outside this workspace.
export function legacyOutputs(generated: string): Record<string, string[]> {
	const result: Record<string, string[]> = {};
	function own(id: string, directory: string) {
		const target = contained(generated, directory);
		if (fs.statSync(target, { throwIfNoEntry: false })?.isDirectory()) (result[id] ??= []).push(directory);
	}
	function ownedBy(directory: string, source: string) {
		const file = contained(generated, directory + "/.dependency.json");
		if (!fs.existsSync(file)) return false;
		const marker = readJson(file) as { source?: string; configuration?: string };
		return marker.source === source && /^[a-f0-9]{64}$/.test(marker.configuration ?? "");
	}
	for (const [id, name, repository] of [
		["luau.lute", "lute", "luau-lang/lute"],
		["tools.pandoc", "pandoc", "jgm/pandoc"],
		["tools.actionsLock", "actionsLock", "github/gh-actions-lock"],
	]) {
		if (!ownedBy("packages/" + name, "github.com/" + repository)) continue;
		own(id, "packages/" + name);
		own(id, "binaries/" + name);
		if (name === "lute") own(id, "types/lute");
	}
	const npmMarker = contained(generated, "npm/.install-fingerprint");
	if (fs.existsSync(npmMarker) && /^[a-f0-9]{64}$/.test(fs.readFileSync(npmMarker, "utf8"))) own("workspace.npm", "npm");
	for (const directory of ["packages/yaml", "packages/typescript", "types/node"]) {
		if (ownedBy(directory, "npm")) own("workspace.npm", directory);
	}
	return result;
}
