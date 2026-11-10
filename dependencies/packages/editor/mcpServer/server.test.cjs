"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { spawn } = require("node:child_process");

const root = path.resolve(__dirname, "../../../..");

test("MCP stdio handshake advertises and invokes workspace tools", async () => {
	const child = spawn(process.execPath, [path.join(__dirname, "index.mjs")], {
		cwd: root, stdio: ["pipe", "pipe", "pipe"], windowsHide: true,
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
			protocolVersion: "2026-07-28",
			capabilities: {},
			clientInfo: { name: "template-test", version: "1.0.0" },
		});
		assert.ok(handshake.result?.serverInfo);
		assert.match(handshake.result.instructions, /Use editor_get_problems for live VS Code diagnostics/);
		child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
		const listed = await request("tools/list");
		assert.deepEqual(listed.result.tools.map(tool => tool.name).sort(), ["editor_get_problems", "rules_list"]);
		const result = await request("tools/call", { name: "rules_list", arguments: { id: "declarative-data" } });
		assert.equal(result.result.structuredContent.selected, 1);
		const unavailable = await request("tools/call", { name: "editor_get_problems", arguments: {} });
		assert.equal(unavailable.result.isError, true);
		assert.match(unavailable.result.content[0].text, /Live VS Code Problems unavailable/);
	} finally {
		clearTimeout(timer);
		child.stdin.end();
		child.kill();
	}
});
