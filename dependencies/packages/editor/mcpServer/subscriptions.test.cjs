"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { enableSubscriptions } = require("./subscriptions.cjs");

test("status updates are opt-in, changed-only, and stop after unsubscribe or close", async t => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const handlers = new Map(); const updates = []; let status = 1;
	const server = { registerCapabilities(value) { assert.equal(value.resources.subscribe, true); },
		setRequestHandler(name, schema, handler) { handlers.set(name, handler); },
		sendResourceUpdated: async value => updates.push(value) };
	enableSubscriptions({ server, fromJsonSchema: value => value, getStatus: async () => ({ status }) });
	t.mock.timers.tick(5000); await new Promise(setImmediate); assert.equal(updates.length, 0);
	await handlers.get("resources/subscribe")();
	t.mock.timers.tick(5000); await new Promise(setImmediate); assert.equal(updates.length, 0);
	status = 2; t.mock.timers.tick(5000); await new Promise(setImmediate);
	assert.deepEqual(updates, [{ uri: "workspace://status" }]);
	await handlers.get("resources/unsubscribe")();
	status = 3; t.mock.timers.tick(5000); await new Promise(setImmediate); assert.equal(updates.length, 1);
	await handlers.get("resources/subscribe")(); server.onclose();
	status = 4; t.mock.timers.tick(5000); await new Promise(setImmediate); assert.equal(updates.length, 1);
});
