"use strict";

const { execFileSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { addedLines } = require("./diff.cjs");

const commentsPerReview = 50;
const reportNames = ["rules-audit-findings", "code-review-findings"];

function commentsFor(findings, files) {
  const lines = new Map(files.filter(file => typeof file.patch === "string")
    .map(file => [file.filename, addedLines(file.patch)]));
  const comments = new Map();
  const severity = { error: 0, warning: 1, information: 2 };
  const eligible = findings.filter(item => item && typeof item.source === "string" &&
    typeof item.message === "string" && Object.hasOwn(severity, item.severity) &&
    !item.fixture && !item.infrastructure && lines.get(item.file)?.has(item.line));
  eligible.sort((a, b) => severity[a.severity] - severity[b.severity] ||
    a.file.localeCompare(b.file) || a.line - b.line);
  for (const item of eligible) {
    const text = (item.source + " [" + item.severity + "]\n" + item.message)
      .replace(/[\x00-\x1f\x7f`~]/g, char => char === "\n" ? "\n" : " ").slice(0, 2000);
    const key = createHash("sha256").update(JSON.stringify([item.file, item.line, text])).digest("hex");
    comments.set(key, {
      path: item.file,
      line: item.line,
      side: "RIGHT",
      body: "<!-- template-review:" + key + " -->\n~~~text\n" + text + "\n~~~",
    });
  }
  return comments;
}

function gh(args, input) {
  return execFileSync("gh", args, { input, encoding: "utf8", timeout: 45000, maxBuffer: 24 * 1024 * 1024 });
}

function api(endpoint, paginated = false) {
  const data = JSON.parse(gh(["api", endpoint, ...(paginated ? ["--paginate", "--slurp"] : [])]));
  return paginated ? data.flat() : data;
}

function main(env = process.env) {
  const { GITHUB_REPOSITORY: repository, PR_NUMBER: pr, REQUEST_SHA: sha, ENGINE_RUN_ID: run, RUNNER_TEMP: temp } = env;
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository) || !/^[1-9]\d*$/.test(pr) ||
    !/^[1-9]\d*$/.test(run) || !/^[a-f0-9]{40}$/.test(sha)) throw new Error("Invalid review identifiers");
  const endpoint = "repos/" + repository + "/pulls/" + pr;
  const isCurrent = () => {
    const pull = api(endpoint);
    return pull.state === "open" && pull.head.sha === sha;
  };
  if (!isCurrent()) return;
  const artifacts = api("repos/" + repository + "/actions/runs/" + run + "/artifacts?per_page=100").artifacts;
  const findings = [];
  for (const name of reportNames) {
    if (!artifacts.some(item => item.name === name && !item.expired && item.size_in_bytes <= 4 * 1024 * 1024)) continue;
    const directory = fs.mkdtempSync(path.join(temp, "template-diagnostics-"));
    try {
      gh(["run", "download", run, "--repo", repository, "--name", name, "--dir", directory]);
      const file = path.join(directory, "diagnostics.json");
      const stat = fs.lstatSync(file, { throwIfNoEntry: false });
      if (!stat?.isFile() || stat.size > 8 * 1024 * 1024) continue;
      const report = JSON.parse(fs.readFileSync(file, "utf8"));
      if (report.version === 1 && Array.isArray(report.diagnostics)) findings.push(...report.diagnostics);
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  }
  if (!findings.length) return; // The engine can fail before producing diagnostics.
  const comments = commentsFor(findings, api(endpoint + "/files?per_page=100", true));
  if (!comments.size) return;
  for (const comment of api(endpoint + "/comments?per_page=100", true)) {
    if (comment.user?.login !== "github-actions[bot]" || comment.original_commit_id !== sha) continue;
    const key = /^<!-- template-review:([a-f0-9]{64}) -->/.exec(comment.body)?.[1];
    if (key) comments.delete(key);
  }
  submitReviews([...comments.values()], isCurrent, comments => {
    gh(["api", "--method", "POST", endpoint + "/reviews", "--input", "-"], JSON.stringify({
      commit_id: sha,
      event: "COMMENT",
      body: "Code Review. See CI artifacts for the full report.",
      comments,
    }));
  });
}

function submitReviews(comments, isCurrent, submit) {
  for (let offset = 0; offset < comments.length; offset += commentsPerReview) {
    if (!isCurrent()) return;
    submit(comments.slice(offset, offset + commentsPerReview));
  }
}

module.exports = { commentsFor, submitReviews };
if (require.main === module) {
  try { main(); }
  catch { console.error("Registry could not publish inline review findings. See the engine run for diagnostics."); process.exitCode = 1; }
}
