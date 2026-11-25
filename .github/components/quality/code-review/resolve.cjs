"use strict";

// The intake run is only a signal. Resolve identity from GitHub's own metadata,
// never from an artifact, PR-controlled script, cache, or workflow output.
const fs = require("node:fs");
const { execFileSync } = require("node:child_process");
const SHA = /^[a-f0-9]{40}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const REF = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const id = n => Number.isSafeInteger(n) && n > 0;

function api(endpoint) {
  return JSON.parse(execFileSync("gh", ["api", "--method", "GET", endpoint], {
    encoding: "utf8", timeout: 30000, maxBuffer: 16 * 1024 * 1024
  }));
}

function resolve(event, mode, get = api, repository = process.env.GITHUB_REPOSITORY) {
  if (!["open", "closed"].includes(mode) || !REPO.test(repository || ""))
    throw new Error("Invalid review resolver context");
  const signal = event.workflow_run;
  const base = "repos/" + repository;
  const file = mode === "open" ? "ci.yml" : "close.yml";
  if (event.action !== "completed" || event.repository?.full_name !== repository ||
      !id(event.repository?.id) || !id(signal?.id) || !id(signal?.run_attempt))
    throw new Error("Invalid workflow completion event");

  const workflow = get(base + "/actions/workflows/" + file);
  const run = get(base + "/actions/runs/" + signal.id);
  if (run.id !== signal.id || run.run_attempt !== signal.run_attempt ||
      run.workflow_id !== workflow.id || workflow.path !== ".github/workflows/" + file ||
      run.repository?.id !== event.repository.id || run.event !== "pull_request" ||
      run.status !== "completed" || (mode === "closed" ? run.conclusion !== "success" : !["success", "failure"].includes(run.conclusion)) ||
      !SHA.test(run.head_sha || "") || !id(run.head_repository?.id))
    throw new Error("Unexpected intake workflow identity");

  const defaultBranch = event.repository.default_branch;
  const numbers = new Set((run.pull_requests || []).map(pr => pr.number).filter(id));
  const headRepo = run.head_repository;
  const branch = run.head_branch;
  const search = new URLSearchParams({ state: mode, base: defaultBranch, per_page: "100" });

  // Fork runs can omit pull_requests entirely. Match the exact head repository,
  // branch and commit through the repository's authoritative PR list.
  if (REPO.test(headRepo.full_name || "") && REF.test(branch || "")) {
    search.set("head", headRepo.full_name.split("/")[0] + ":" + branch);
    for (let page = 1; page <= 10; page++) {
      search.set("page", String(page));
      const list = get(base + "/pulls?" + search);
      if (!Array.isArray(list)) throw new Error("Invalid PR list");
      for (const pr of list) if (id(pr.number)) numbers.add(pr.number);
      if (list.length < 100) break;
      if (page === 10) throw new Error("PR resolution exceeded pagination limit");
    }
  }
  // A merged closure can be reported at its merge commit rather than its head.
  if (mode === "closed" && headRepo.id === event.repository.id) {
    const list = get(base + "/commits/" + run.head_sha + "/pulls?per_page=100");
    if (!Array.isArray(list) || list.length >= 100) throw new Error("Ambiguous commit PR association");
    for (const pr of list) if (id(pr.number)) numbers.add(pr.number);
  }

  const matches = [];
  for (const number of numbers) {
    const pr = get(base + "/pulls/" + number);
    if (pr.number !== number || pr.state !== mode ||
        pr.base?.repo?.id !== event.repository.id || pr.base.ref !== defaultBranch ||
        !SHA.test(pr.head?.sha || "") || !REF.test(pr.head?.ref || "") ||
        pr.head.ref.includes("..") || pr.head.ref.includes("//")) continue;
    const exact = pr.head.repo?.id === headRepo.id &&
      pr.head.ref === branch && pr.head.sha === run.head_sha;
    const merged = mode === "closed" && pr.merged === true &&
      pr.head.repo?.id === event.repository.id && headRepo.id === event.repository.id &&
      pr.merge_commit_sha === run.head_sha;
    if (!exact && !merged) continue;
    if (mode === "closed" && pr.head.repo?.id !== event.repository.id) continue;
    matches.push({ pr: String(number), sha: pr.head.sha, ref: "refs/heads/" + pr.head.ref });
  }
  if (matches.length > 1) throw new Error("Ambiguous intake PR association");
  return matches[0] || null;
}

module.exports = { resolve };
if (require.main === module) {
  try {
    if (process.env.GITHUB_EVENT_NAME !== "workflow_run") throw new Error("Trusted workflow_run required");
    const result = resolve(JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, "utf8")), process.argv[2]);
    if (!result) console.log("No current matching PR; nothing to dispatch");
    else for (const [key, value] of Object.entries(result))
      fs.appendFileSync(process.env.GITHUB_OUTPUT, key + "=" + value + "\n");
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
