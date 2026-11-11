"use strict";

const path = require("node:path");
const { connect } = require("../workbenchBridgeClient");

const { selectedSession } = require("../editorIntegration/session.cjs");

function normalizeFile(file) {
	if (file === undefined) return undefined;
	if (typeof file !== "string" || !file || path.isAbsolute(file) || /^[A-Za-z]:/.test(file)) {
		throw new TypeError("file must be a workspace-relative path");
	}
	const normalized = path.posix.normalize(file.replaceAll("\\", "/"));
	if (normalized === ".." || normalized.startsWith("../") || normalized.startsWith("/")) {
		throw new TypeError("file must remain inside the workspace");
	}
	return normalized.replace(/^\.\//, "");
}

async function getProblems({ root, file, severity, limit = 25, connectBridge = connect }) {
	if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new RangeError("limit must be an integer between 1 and 100");
	if (severity !== undefined && !["error", "warning", "information", "hint"].includes(severity)) throw new TypeError("Invalid diagnostic severity");
	const selectedFile = normalizeFile(file);
	let bridge;
	try {
		bridge = await connectBridge({ workspace: root, sessionFile: selectedSession(root) });
		const module = await bridge.loadModule({ path: "dependencies/packages/editor/editorIntegration/problems.cjs" });
		const reference = await bridge.call({ target: module, path: ["snapshot"], args: [] });
		const snapshot = await bridge.snapshot({ target: reference });
		if (!Array.isArray(snapshot)) throw new TypeError("Workbench Bridge returned an invalid Problems snapshot");

		const found = snapshot.filter(problem =>
			(!selectedFile || problem.file === selectedFile) && (!severity || problem.severity === severity));
		found.sort((a, b) => a.file.localeCompare(b.file) ||
			a.line - b.line || a.column - b.column ||
			String(a.severity).localeCompare(String(b.severity)) ||
			String(a.message).localeCompare(String(b.message)));
		return {
			workspace: root,
			filters: { ...(selectedFile ? { file: selectedFile } : {}), ...(severity ? { severity } : {}) },
			total: found.length,
			counts: Object.fromEntries(["error", "warning", "information", "hint"].map(kind =>
				[kind, found.filter(problem => problem.severity === kind).length])),
			truncated: found.length > limit,
			diagnostics: found.slice(0, limit),
			note: "Diagnostics reflect the current VS Code snapshot and may lag an edit.",
		};
	} catch (error) {
		throw new Error(`Live VS Code Problems unavailable: ${error instanceof Error ? error.message : String(error)}`);
	} finally {
		bridge?.close();
	}
}

module.exports = { getProblems, normalizeFile, selectedSession };
