"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { connect } = require("../workbenchBridgeClient");
const { getProblems, normalizeFile, selectedSession } = require("./problems.cjs");
const ci = require("./ci.cjs");

async function documentOperation({ root, operation, args, connectBridge = connect, allowWrites = process.env.WORKSPACE_MCP_ALLOW_WRITES === "1" }) {
	if (!["getDocument", "applyEdit"].includes(operation)) throw new Error("UNSUPPORTED_CAPABILITY: use editor_get_document or workspace_apply_edit");
	if (operation === "applyEdit" && (!allowWrites || args.authorize !== true)) throw new Error("WRITE_NOT_AUTHORIZED: enable WORKSPACE_MCP_ALLOW_WRITES=1 in the server environment and explicitly authorize this workspace_apply_edit call");
	const file = normalizeFile(args.file);
	if (!file) throw new Error("INVALID_FILE: editor_get_document and workspace_apply_edit require file");
	let bridge;
	try {
		try { bridge = await connectBridge({ workspace: root, sessionFile: selectedSession(root) }); }
		catch (error) { throw new Error(`EDITOR_UNAVAILABLE: ${error.message}. Open a trusted workspace with Workbench Bridge or select WORKBENCH_BRIDGE_SESSION for ambiguous sessions.`); }
		const module = await bridge.loadModule({ path: "dependencies/packages/editor/editorIntegration/documents.cjs" });
		const reference = await bridge.call({ target: module, path: [operation], args: [{ ...args, file }] });
		return await bridge.snapshot({ target: reference });
	} catch (error) {
		throw new Error(`${operation === "applyEdit" ? "workspace_apply_edit" : "editor_get_document"} unavailable: ${error.message}`, { cause: error });
	} finally { bridge?.close(); }
}

async function getStatus({ root, problems = getProblems }) {
	let editor, diagnostics;
	try {
		const result = await problems({ root, limit: 1 });
		editor = { connected: true };
		diagnostics = { available: true, counts: result.counts, total: result.total, note: result.note };
	} catch (error) {
		editor = { connected: false, reason: error.message, action: "Open a trusted VS Code workspace with Workbench Bridge; select WORKBENCH_BRIDGE_SESSION if sessions are ambiguous. Use editor_get_problems to retry." };
		diagnostics = { available: false };
	}
	let dependencies;
	try {
		const state = JSON.parse(fs.readFileSync(path.join(root, "dependencies/managed/.loader-state.json"), "utf8"));
		const entries = Object.values(state.entries);
		const missing = entries.flatMap(entry => entry.outputs).filter(output => typeof output !== "string" || path.isAbsolute(output) || output.split(/[\\/]/).includes("..") || !fs.existsSync(path.join(root, "dependencies/managed", output)));
		dependencies = { available: true, installedEntries: entries.length, outputsPresent: missing.length === 0, missingOutputs: missing.length,
			verification: "Recorded installation and output existence only; run the dependency loader to verify lock freshness and platform readiness." };
	} catch { dependencies = { available: false, action: "Run node dependencies/packages/core/dependencyLoader/index.ts to establish dependency readiness." }; }
	const status = ci.getStatus({ root, limit: 3 });
	return { editor, dependencies, diagnostics, ci: status, writes: { enabled: process.env.WORKSPACE_MCP_ALLOW_WRITES === "1", capability: "workspace_apply_edit", requires: "authorize=true and current document version" } };
}
module.exports = { documentOperation, getStatus };
