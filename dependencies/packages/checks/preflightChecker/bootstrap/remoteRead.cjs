"use strict";

const fs = require("node:fs");

async function inspect(inputs, repository, token, fetcher = fetch) {
	if (!/^[\w.-]+\/[\w.-]+$/.test(repository ?? "") ||
		inputs.repository.toLowerCase() !== repository.toLowerCase() || !token) {
		throw new Error("The configured repository must match this Actions run and a read token is required.");
	}
	const prefix = "https://api.github.com/repos/" + repository;
	const headers = {
		Authorization: "Bearer " + token,
		Accept: "application/vnd.github+json",
		"X-GitHub-Api-Version": "2022-11-28",
		"User-Agent": "Template-Preflight",
	};
	async function read(resource, name) {
		const segments = { repository: "", label: "/labels/", branch: "/branches/" };
		if (!Object.hasOwn(segments, resource) ||
			(resource !== "repository" && (!name || name === "." || name === ".."))) {
			throw new Error("Unapproved remote read.");
		}
		const url = prefix + segments[resource] + (name ? encodeURIComponent(name) : "");
		try {
			const response = await fetcher(url, {
				method: "GET", redirect: "error", headers, signal: AbortSignal.timeout(10_000),
			});
			return { status: response.status, value: response.ok ? await response.json() : undefined };
		} catch {
			return { status: null };
		}
	}

	const observed = await read("repository");
	const defaultBranch = observed.value?.default_branch;
	const checks = [];
	const record = (operation, name, status, reason) => checks.push({ operation, name, status, reason });
	for (const { name } of inputs.labels) {
		const result = await read("label", name);
		if (typeof result.value?.name === "string" && result.value.name.toLowerCase() === name.toLowerCase()) {
			const archived = result.value.archived_at;
			record("label", name, archived == null ? "passed" : "failed",
				archived == null ? "Active label" : "Configured label is archived");
		} else {
			record("label", name, "unverified", result.status === 404
				? "Label absent or hidden from this token. Creation acceptance remains unverified."
				: "Unable to establish label state");
		}
	}

	for (const name of inputs.branches) {
		if (name === defaultBranch) {
			record("branch", name, "failed", "Publication would target the repository default branch");
			continue;
		}
		const result = await read("branch", name);
		if (defaultBranch && result.value?.name === name) {
			record("branch", name, "passed", "Destination exists");
		} else {
			record("branch", name, "unverified", result.status === 404
				? "Destination absent or hidden from this token. Creation acceptance remains unverified."
				: "Unable to establish destination state");
		}
	}

	if (!defaultBranch) record("repository", repository, "unverified", "Unable to read the repository default branch");
	const status = checks.some(check => check.status === "failed") ? "failed"
		: checks.length && checks.every(check => check.status === "passed") ? "passed" : "incomplete";
	return { status, requestValidation: "not run", livePrerequisites: checks, writeAcceptance: "unverified" };
}

if (require.main === module) {
	(async () => {
		const inputs = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
		const report = await inspect(inputs, process.env.GITHUB_REPOSITORY, process.env.GH_TOKEN);
		console.log(JSON.stringify(report, null, 2));
		if (report.status !== "passed") process.exitCode = 1;
	})().catch(() => {
		console.error("Remote read could not start. Check the input file, repository configuration, and read token.");
		process.exitCode = 1;
	});
}

module.exports = { inspect };
