"use strict";

// Offline, read-only onboarding/readiness inspection. This is intentionally
// usable before installing the managed dependency graph.
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { configFromFile } = require("../template-updates/version.cjs");

const ROOT = path.resolve(__dirname, "../../../..");
const REQUIRED = [
  ".github/workflows/bootstrap.yml",
  ".github/workflows/push.yml",
  ".github/workflows/pull.yml",
  ".github/workflows/close.yml",
  ".github/workflows/manual.yml",
  ".github/workflows/remote.yml",
  "config/ci/operations.json",
  "config/targets.toml",
  "config/template.json",
  "config/branches/main.toml",
  ".github/components/governance/branches/build/init.luau",
  ".github/components/governance/branches/publish/init.luau",
  "dependencies/dependencies.json",
  "dependencies/dependencies.lock",
];

function parseRepositoryRemote(value) {
  if (!value || typeof value !== "string") return null;
  const remote = value.trim().replace(/\.git\/?$/, "");
  const match = remote.match(/^(?:https?:\/\/(?:[^@\s/]+@)?github\.com\/|ssh:\/\/git@github\.com\/|git@github\.com:)([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)$/);
  return match ? match[1] : null;
}

function git(args, directory = ROOT) {
  const result = spawnSync("git", args, { cwd: directory, encoding: "utf8", timeout: 3000, windowsHide: true });
  return result.status === 0 ? result.stdout.trim() : null;
}

function identity(env = process.env, directory = ROOT) {
  const repository = /^[\w.-]+\/[\w.-]+$/.test(env.GITHUB_REPOSITORY || "")
    ? env.GITHUB_REPOSITORY
    : parseRepositoryRemote(git(["remote", "get-url", "origin"], directory));
  let branch = env.CI_DEFAULT_BRANCH || env.GITHUB_DEFAULT_BRANCH || null;
  if (!branch && env.GITHUB_EVENT_PATH && fs.existsSync(env.GITHUB_EVENT_PATH)) {
    try { branch = JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, "utf8")).repository?.default_branch; }
    catch { /* Invalid event context is handled as unknown, not guessed. */ }
  }
  if (!branch) {
    const symbolic = git(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], directory);
    if (symbolic) branch = symbolic.replace(/^origin\//, "");
  }
  return { repository, defaultBranch: branch || null };
}

function targetRepository(text) {
  let section = null;
  for (const line of text.split(/\r?\n/)) {
    const header = /^\s*\[([^\]]+)\]\s*$/.exec(line);
    if (header) { section = header[1]; continue; }
    if (section === "github") {
      const match = /^\s*repository\s*=\s*"([^"]+)"\s*$/.exec(line);
      if (match) return match[1];
    }
  }
  return null;
}

function analyze(directory = ROOT, env = process.env) {
  const issues = [];
  const notes = [];
  for (const required of REQUIRED) {
    if (!fs.existsSync(path.join(directory, required))) issues.push("Missing required file: " + required);
  }
  const project = identity(env, directory);
  let version = null, operation = null, declaredTarget = null, pushOperation = null;
  try { version = configFromFile(path.join(directory, "config/template.json")); }
  catch (error) { issues.push("Template metadata: " + error.message); }
  try {
    operation = JSON.parse(fs.readFileSync(path.join(directory, "config/ci/operations.json"), "utf8"));
    const callers = ["pull", "push"];
    const eventNames = { pull: "pull_request", push: "push" };
    for (const caller of callers) {
      const source = fs.readFileSync(path.join(directory, ".github/workflows", caller + ".yml"), "utf8");
      const selected = [...new Set([...source.matchAll(/^          CI_OPERATION:\s*([a-z][a-z0-9-]*)\s*$/gm)]
        .map(match => match[1]).filter(name => operation.operations?.[name]?.events?.includes(eventNames[caller])))];
      if (selected.length !== 1) issues.push("CI entry point has no unique " + caller + " operation");
      else if (caller === "push") pushOperation = selected[0];
    }
  } catch (error) { issues.push("CI operations: " + error.message); }
  try {
    declaredTarget = targetRepository(fs.readFileSync(path.join(directory, "config/targets.toml"), "utf8"));
    if (!declaredTarget) issues.push("GitHub repository target is missing");
    else if (declaredTarget !== "current" && project.repository && declaredTarget.toLowerCase() !== project.repository.toLowerCase())
      issues.push("GitHub target " + declaredTarget + " does not match " + project.repository + "; set github.repository = \"current\"");
  } catch (error) { issues.push("GitHub targets: " + error.message); }
  const branchSource = path.join(directory, "config/branches/main.toml");
  if (fs.existsSync(branchSource) && !/\[branch\]/.test(fs.readFileSync(branchSource, "utf8"))) {
    issues.push("Main branch generation record is missing its [branch] declaration");
  }
  if (!project.repository) notes.push("GitHub repository identity unavailable offline; it is resolved from GITHUB_REPOSITORY on GitHub.");
  if (!project.defaultBranch) notes.push("Default branch unknown locally; GitHub Actions resolves it from the repository event.");
  const publishing = operation?.operations?.[pushOperation]?.publication === true;
  if (publishing) notes.push("Automatic publication is enabled. Configure the ci-bootstrap environment and scoped credentials, or select an OIDC-enabled publisher before publishing.");
  else notes.push("Default pushes run read-only CI. Publishing is optional and must be explicitly enabled in operations.json.");
  if (project.defaultBranch === "main") notes.push("Generated branch 'main' already matches the default branch. The branch publisher will skip it rather than overwrite it.");
  notes.push("A successful readiness check does not prove marketplace trust registration or GitHub environment secret availability.");
  return {
    ready: issues.length === 0,
    repository: project.repository,
    defaultBranch: project.defaultBranch,
    configuredRepository: declaredTarget,
    templateVersion: version?.installed || null,
    pushOperation,
    generatedBranchConfigured: fs.existsSync(branchSource),
    publicationEnabled: publishing,
    issues, notes,
  };
}

function present(report) {
  return [
    "Template readiness: " + (report.ready ? "configuration valid" : "configuration incomplete"),
    "Repository: " + (report.repository || "(detected on GitHub)"),
    "Default branch: " + (report.defaultBranch || "(detected on GitHub)"),
    "Repository target: " + (report.configuredRepository || "(missing)"),
    "Installed Template: " + (report.templateVersion || "(unavailable)"),
    "Default push: " + (report.pushOperation || "(missing)"),
    "Generated branch support: " + (report.generatedBranchConfigured ? "configured" : "missing"),
    ...report.issues.map(x => "ERROR: " + x),
    ...report.notes.map(x => "Note: " + x),
  ].join("\n") + "\n";
}

function main(args = process.argv.slice(2)) {
  if (args.includes("--help")) {
    process.stdout.write("Usage: node .github/components/quality/setup/readiness.cjs [--json]\nRead-only setup audit; no secrets or repository settings are modified.\n");
    return;
  }
  if (args.some(x => x !== "--json")) throw new Error("Unknown setup flag");
  const result = analyze();
  process.stdout.write(args.includes("--json") ? JSON.stringify(result, null, 2) + "\n" : present(result));
  if (!result.ready) process.exitCode = 1;
}

module.exports = { parseRepositoryRemote, targetRepository, identity, analyze, present, main };
if (require.main === module) {
  try { main(); } catch (error) { console.error("::error::" + error.message); process.exitCode = 1; }
}
