"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const [operation, ...values] = process.argv.slice(2);

function nativePath(value) {
	if (process.platform === "win32" && /^\/[A-Za-z]\//.test(value)) {
		return `${value[1]}:${value.slice(2).replaceAll("/", "\\")}`;
	}
	const windowsPath = value.match(/^([A-Za-z]):[\\/](.*)$/);
	if (process.platform !== "win32" && windowsPath) {
		return path.join("/mnt", windowsPath[1].toLowerCase(), windowsPath[2].replaceAll("\\", "/"));
	}
	return value;
}

function hashFile(file) {
	return crypto.createHash("sha256").update(fs.readFileSync(nativePath(file))).digest("hex");
}

switch (operation) {
	case "identity": {
		const manifest = JSON.parse(fs.readFileSync(".vscode/preflight/package.json", "utf8"));
		process.stdout.write(`${manifest.publisher}.${manifest.name}`);
		break;
	}
	case "source-hash": {
		const hash = crypto.createHash("sha256");
		for (const file of values) {
			hash.update(file);
			hash.update("\0");
			hash.update(fs.readFileSync(nativePath(file)));
		}
		process.stdout.write(hash.digest("hex"));
		break;
	}
	case "version": {
		const manifest = JSON.parse(fs.readFileSync(".vscode/preflight/package.json", "utf8"));
		process.stdout.write(manifest.version);
		break;
	}
	case "file-hash":
		process.stdout.write(hashFile(values[0]));
		break;
	case "installed-hash":
		try {
			process.stdout.write(hashFile(path.join(nativePath(values[0]), "extension.js")));
		} catch {
			// An absent extension has no installed hash.
		}
		break;
	case "is-installed": {
		const identity = values[0].toLowerCase();
		const entries = fs.readFileSync(0, "utf8").split(/\r?\n/);
		if (entries.some((entry) => entry.trim().toLowerCase() === identity)) {
			process.stdout.write("true");
		}
		break;
	}
	default:
		throw new Error(`Unknown Preflight setup operation: ${operation}`);
}
