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

// Only reconcile threads created by our own review publisher. Never resolve
// a human discussion, even when the original bot finding has disappeared.
function owned(thread) {
  const first = thread.comments?.nodes?.[0];
  return first && ["github-actions", "github-actions[bot]"].includes(first.author?.login) &&
    /^<!-- template-review:[a-f0-9]{64} -->\n/.test(first.body || "");
}

function signature(file, line, body) {
  return JSON.stringify([file, line, body.replace(/^<!-- template-review:[a-f0-9]{64} -->\n/, "")]);
}

function reconcile(desired, threads, complete, files) {
  const remaining = new Map(desired);
  const wanted = new Map([...desired].map(([key, item]) => [signature(item.path, item.line, item.body), key]));
  const covered = new Set();
  const resolve = [];
  const unavailable = new Set(files.filter(file => typeof file.patch !== "string").map(file => file.filename));

  // Prefer existing human discussions, then unresolved bot-only threads.
  const ordered = [...threads].sort((a, b) =>
    Number(b.comments.totalCount > 1) - Number(a.comments.totalCount > 1) ||
    Number(a.isResolved) - Number(b.isResolved));
  for (const thread of ordered) {
    if (!owned(thread)) continue;
    const root = thread.comments.nodes[0];
    const key = !thread.isOutdated && Number.isInteger(thread.line) && thread.diffSide === "RIGHT"
      ? wanted.get(signature(thread.path, thread.line, root.body)) : undefined;
    if (key && !covered.has(key)) {
      covered.add(key);
      remaining.delete(key);
      continue;
    }
    if (complete && !thread.isResolved && thread.comments.totalCount === 1 &&
        (thread.isOutdated || !unavailable.has(thread.path))) resolve.push(thread.id);
  }
  return { comments: [...remaining.values()], resolve };
}

function graphql(query, variables) {
  const result = JSON.parse(gh(["api", "graphql", "--input", "-"], JSON.stringify({ query, variables })));
  if (result.errors?.length || !result.data) throw new Error("Review thread GraphQL request failed");
  return result.data;
}

function reviewThreads(repository, pr) {
  const [owner, name] = repository.split("/");
  const query = `query($owner:String!, $name:String!, $number:Int!, $cursor:String) {
    repository(owner:$owner,name:$name) { pullRequest(number:$number) {
      reviewThreads(first:100,after:$cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { id isResolved isOutdated path line diffSide
          comments(first:1) { totalCount nodes { body author { login } } } }
      }
    } }
  }`;
  const threads = [];
  let cursor = null;
  for (let page = 0; page < 100; page++) {
    const result = graphql(query, { owner, name, number: Number(pr), cursor }).repository?.pullRequest?.reviewThreads;
    if (!result || !Array.isArray(result.nodes)) throw new Error("Missing review threads");
    threads.push(...result.nodes);
    if (!result.pageInfo.hasNextPage) return threads;
    cursor = result.pageInfo.endCursor;
    if (!cursor) throw new Error("Missing review thread cursor");
  }
  throw new Error("Review thread pagination exceeded limit");
}

function resolveThread(id) {
  graphql("mutation($id:ID!) { resolveReviewThread(input:{threadId:$id}) { thread { id isResolved } } }", { id });
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
  let completeReports = 0;
  for (const name of reportNames) {
    if (!artifacts.some(item => item.name === name && !item.expired && item.size_in_bytes <= 4 * 1024 * 1024)) continue;
    const directory = fs.mkdtempSync(path.join(temp, "template-diagnostics-"));
    try {
      gh(["run", "download", run, "--repo", repository, "--name", name, "--dir", directory]);
      const file = path.join(directory, "diagnostics.json");
      const stat = fs.lstatSync(file, { throwIfNoEntry: false });
      if (!stat?.isFile() || stat.size > 8 * 1024 * 1024) continue;
      const report = JSON.parse(fs.readFileSync(file, "utf8"));
      if (report.version === 1 && Array.isArray(report.diagnostics)) {
        findings.push(...report.diagnostics);
        if (Array.isArray(report.changedFiles) && !report.diagnostics.some(item => !item || item.infrastructure))
          completeReports++;
      }
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  }
  // An empty, complete report is meaningful: all previous findings may be fixed.
  // Incomplete reports may add findings but cannot clear previous findings.
  if (!findings.length && completeReports !== reportNames.length) return;
  const files = api(endpoint + "/files?per_page=100", true);
  const pull = api(endpoint);
  if (pull.state !== "open" || pull.head.sha !== sha) return;
  const complete = completeReports === reportNames.length && files.length === pull.changed_files;
  const desired = commentsFor(findings, files);
  const plan = reconcile(desired, reviewThreads(repository, pr), complete, files);
  // Resolve before posting replacements. Recheck the head before every write.
  // Query each candidate again so a newly added human reply is not closed.
  for (const id of plan.resolve) {
    if (!isCurrent()) return;
    const current = graphql(`query($id:ID!) { node(id:$id) {
      ... on PullRequestReviewThread { id isResolved
        comments(first:1) { totalCount nodes { body author { login } } }
      }
    } }`, { id }).node;
    if (!current || current.isResolved || current.comments.totalCount !== 1 || !owned(current)) continue;
    if (!isCurrent()) return;
    resolveThread(id);
  }
  submitReviews(plan.comments, isCurrent, comments => {
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

module.exports = { commentsFor, submitReviews, reconcile };
if (require.main === module) {
  try { main(); }
  catch { console.error("Registry could not publish inline review findings. See the engine run for diagnostics."); process.exitCode = 1; }
}
