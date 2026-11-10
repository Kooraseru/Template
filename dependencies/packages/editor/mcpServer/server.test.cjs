"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { spawn } = require("node:child_process");

const root = path.resolve(__dirname, "../../../..");

for (const protocolVersion of ["2025-11-25", "2026-07-28"]) test("MCP stdio handshake advertises and invokes workspace tools (" + protocolVersion + ")", async () => {
	const child = spawn(process.execPath, [path.join(__dirname, "index.mjs")], {
		cwd: root, env: { ...process.env, WORKSPACE_MCP_ALLOW_WRITES: "0" }, stdio: ["pipe", "pipe", "pipe"], windowsHide: true,
	});
	const pending = new Map();
	let buffer = "";
	let stderr = "";
	let nextId = 0;
	child.stderr.setEncoding("utf8");
	child.stderr.on("data", chunk => { stderr += chunk; });
	child.stdout.setEncoding("utf8");
	child.stdout.on("data", chunk => {
		buffer += chunk;
		const lines = buffer.split(/\r?\n/);
		buffer = lines.pop();
		for (const line of lines) {
			if (!line) continue;
			const value = JSON.parse(line);
			const entry = pending.get(value.id);
			if (entry) {
				pending.delete(value.id);
				entry.resolve(value);
			}
		}
	});
	const request = (method, params = {}) => new Promise((resolve, reject) => {
		const id = ++nextId;
		pending.set(id, { resolve, reject });
		child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
	});
	const timer = setTimeout(() => {
		for (const entry of pending.values()) entry.reject(new Error("MCP response timed out: " + stderr));
		pending.clear();
	}, 10000);
	try {
		const handshake = await request("initialize", {
			protocolVersion,
			capabilities: {},
			clientInfo: { name: "template-test", version: "1.0.0" },
		});
		assert.ok(handshake.result?.serverInfo);
		assert.match(handshake.result.instructions, /Use editor_get_problems for live VS Code diagnostics/);
		child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
		const listed = await request("tools/list");
		assert.deepEqual(listed.result.tools.map(tool => tool.name).sort(), ["ci_get_status", "editor_get_document", "editor_get_problems", "rules_list", "workspace_apply_edit", "workspace_status"]);
		const writeTool = listed.result.tools.find(tool => tool.name === "workspace_apply_edit");
		assert.equal(writeTool.annotations.readOnlyHint, false);
		const denied = await request("tools/call", { name: "workspace_apply_edit", arguments: { file: "AGENTS.md", version: 1, authorize: true, edits: [{ start: 0, end: 0, text: "test" }] } });
		assert.equal(denied.result.isError, true);
		assert.match(denied.result.content[0].text, /WRITE_NOT_AUTHORIZED/);
		const status = await request("tools/call", { name: "workspace_status", arguments: {} });
		assert.equal(typeof status.result.structuredContent.editor.connected, "boolean");
		const ci = await request("tools/call", { name: "ci_get_status", arguments: {} });
		assert.ok(Array.isArray(ci.result.structuredContent.workflows));
		const subscription = await request("resources/subscribe", { uri: "workspace://status" });
		assert.deepEqual(subscription.result, {});
		const unsubscribed = await request("resources/unsubscribe", { uri: "workspace://status" });
		assert.deepEqual(unsubscribed.result, {});
		const resource = await request("resources/read", { uri: "workspace://status" });
		assert.ok(JSON.parse(resource.result.contents[0].text).dependencies);
		const invalid = await request("tools/call", { name: "editor_get_document", arguments: { file: "../escape" } });
		assert.equal(invalid.result.isError, true);
		const result = await request("tools/call", { name: "rules_list", arguments: { id: "declarative-data" } });
		assert.equal(result.result.structuredContent.selected, 1);
		const diagnostics = await request("tools/call", { name: "editor_get_problems", arguments: {} });
		if (diagnostics.result.isError) {
			assert.match(diagnostics.result.content[0].text, /Live VS Code Problems unavailable/);
		} else {
			assert.ok(Array.isArray(diagnostics.result.structuredContent.diagnostics));
		}
	} finally {
		clearTimeout(timer);
		child.stdin.end();
		child.kill();
	}
});
