"use strict";

const http = require("node:http");
const assert = require("node:assert/strict");
const Ajv = require("../../../../../dependencies/managed/npm/node_modules/ajv");
const validateLabelCreate = new Ajv().compile(require("./githubLabelCreate.schema.json"));

async function startMock({ repository, labels }, scenario) {
	const prefix = "/repos/" + repository;
	const catalog = new Map(labels.map(label => [label.name, label]));
	const first = labels[0]?.name;
	const state = new Map(labels.map(label => [label.name, { ...label, archived_at: null }]));
	if (scenario === "create") state.delete(first);
	if (scenario === "archived" && first) state.get(first).archived_at = "2025-01-01T00:00:00Z";
	const violations = [];
	const operations = [];
	const server = http.createServer(async (request, response) => {
		const send = (status, data, json = true) => {
			response.writeHead(status, { "content-type": json ? "application/json" : "text/plain" });
			response.end(json ? JSON.stringify(data) : data);
		};
		try {
			assert.equal(request.headers.authorization, "Bearer rehearsal-token");
			assert.equal(request.headers.accept, "application/vnd.github+json");
			assert.equal(request.headers["x-github-api-version"], "2022-11-28");
			assert.equal(request.headers["user-agent"], "Template-CI");
			const { method } = request;
			const url = new URL(request.url, "http://127.0.0.1");
			let body = "";
			for await (const chunk of request) {
				body += chunk;
				assert.ok(body.length <= 16384);
			}
			if (method === "GET") assert.equal(body, "");
			if (method === "GET" && url.pathname === prefix && !url.search) {
				operations.push("read repository");
				return send(200, { default_branch: "source" });
			}
			const collection = prefix + "/labels";
			if (method === "GET" && url.pathname === collection) {
				assert.deepEqual([...url.searchParams], [["per_page", "100"], ["page", "1"]]);
				operations.push("list labels");
				return send(200, [...state.values()]);
			}
			if (method === "GET" && url.pathname.startsWith(collection + "/") && !url.search) {
				const name = decodeURIComponent(url.pathname.slice(collection.length + 1));
				assert.ok(catalog.has(name));
				operations.push("read label");
				if (name === first && scenario === "malformed") return send(200, "{", false);
				if (name === first && scenario === "http-error") return send(503, "Service unavailable", false);
				return state.has(name) ? send(200, state.get(name)) : send(404, { message: "Not Found" });
			}
			if (method === "POST" && url.pathname === collection && !url.search) {
				assert.equal(scenario, "create");
				assert.equal(request.headers["content-type"], "application/json");
				const label = JSON.parse(body);
				assert.ok(validateLabelCreate(label));
				assert.equal(label.name, first);
				assert.ok(!state.has(first));
				assert.deepEqual(label, catalog.get(first));
				state.set(first, { ...label, archived_at: null });
				operations.push("create label");
				return send(201, state.get(first));
			}
			throw new Error("Unexpected operation");
		} catch {
			violations.push("Unexpected GitHub operation, headers, query, or JSON fields.");
			send(422, { message: violations.at(-1) });
		}
	});
	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(47831, "127.0.0.1", resolve);
	});
	return {
		server, violations, operations,
		assertLabels() {
			assert.deepEqual(state, new Map(labels.map(label => [label.name, { ...label, archived_at: null }])));
			assert.equal(operations.filter(operation => operation === "read label").length, labels.length);
			assert.equal(operations.filter(operation => operation === "create label").length, scenario === "create" ? 1 : 0);
		},
	};
}

module.exports = { startMock };
