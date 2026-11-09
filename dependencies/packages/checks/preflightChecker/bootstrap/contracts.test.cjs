"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { startMock } = require("./githubMock.cjs");
const { inspect } = require("./remoteRead.cjs");

const repository = "owner/project";
const label = { name: "bug", color: "d73a4a", description: "Bug" };
const inputs = { repository, labels: [label], branches: ["main"] };

test("mock rejects bad headers, unknown routes, and malformed fields", async () => {
	const mock = await startMock(inputs, "create");
	const base = "http://127.0.0.1:47831/repos/" + repository;
	const headers = {
		authorization: "Bearer rehearsal-token",
		accept: "application/vnd.github+json",
		"x-github-api-version": "2022-11-28",
		"user-agent": "Template-CI",
		"content-type": "application/json",
	};
	try {
		assert.equal((await fetch(base)).status, 422);
		assert.equal((await fetch(base + "/unexpected", { headers })).status, 422);
		assert.equal((await fetch(base + "/labels", {
			headers, method: "POST", body: JSON.stringify({ ...label, extra: true }),
		})).status, 422);
		assert.equal((await fetch(base + "/labels", {
			headers, method: "POST", body: JSON.stringify(label),
		})).status, 201);
		assert.equal((await fetch(base + "/labels/bug", { headers })).status, 200);
		assert.equal(mock.violations.length, 3);
		mock.assertLabels();
	} finally {
		mock.server.close();
	}
});

test("remote reader sends only scoped GETs and keeps writes unverified", async () => {
	const calls = [];
	const fetcher = async (url, options) => {
		calls.push(url);
		assert.equal(options.method, "GET");
		assert.equal(options.redirect, "error");
		assert.equal(options.body, undefined);
		if (url.endsWith("/labels/bug")) return Response.json({ name: "bug", archived_at: null });
		if (url.endsWith("/branches/main")) return Response.json({ name: "main" });
		return Response.json({ default_branch: "source" });
	};
	const report = await inspect(inputs, repository, "fake", fetcher);
	assert.equal(report.status, "passed");
	assert.equal(report.writeAcceptance, "unverified");
	assert.deepEqual(calls, ["", "/labels/bug", "/branches/main"].map(suffix =>
		"https://api.github.com/repos/" + repository + suffix));
	await assert.rejects(inspect(inputs, "another/project", "fake", fetcher));
	await assert.rejects(inspect({ ...inputs, branches: [".."] }, repository, "fake", fetcher));
	assert.equal(calls.length, 5);
});

test("remote reader distinguishes an archived label and an unavailable destination", async () => {
	const report = await inspect(inputs, repository, "fake", async url => {
		if (url.endsWith("/labels/bug")) return Response.json({ name: "bug", archived_at: "2025-01-01" });
		if (url.endsWith("/branches/main")) return new Response(null, { status: 403 });
		return Response.json({ default_branch: "source" });
	});
	assert.equal(report.status, "failed");
	assert.deepEqual(report.livePrerequisites.map(check => check.status), ["failed", "unverified"]);
});
