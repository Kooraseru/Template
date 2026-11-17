"use strict";

// Template distribution versions are independent of the consuming application's
// version and of the CI Engine release. No automatic writes or merges.
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "../..");
const CONFIG = path.join(ROOT, "config/template.json");
const VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?$/;
const RELEASE_TAG = /^template\/v(.+)$/;
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const MAX_PAGES = 10;

function parseVersion(value) {
  if (typeof value !== "string") return null;
  const match = VERSION.exec(value);
  if (!match) return null;
  return { numeric: match.slice(1, 4).map(Number), prerelease: match[4] ? match[4].split(".") : [] };
}

function compareVersion(left, right) {
  const a = parseVersion(left), b = parseVersion(right);
  if (!a || !b) throw new Error("Invalid Template semantic version");
  for (let index = 0; index < 3; index++) {
    if (a.numeric[index] !== b.numeric[index]) return a.numeric[index] > b.numeric[index] ? 1 : -1;
  }
  if (!a.prerelease.length && b.prerelease.length) return 1;
  if (a.prerelease.length && !b.prerelease.length) return -1;
  const limit = Math.max(a.prerelease.length, b.prerelease.length);
  for (let index = 0; index < limit; index++) {
    const one = a.prerelease[index], two = b.prerelease[index];
    if (one === undefined) return -1;
    if (two === undefined) return 1;
    if (one === two) continue;
    const oneNumber = /^\d+$/.test(one), twoNumber = /^\d+$/.test(two);
    if (oneNumber && twoNumber) {
      const aNumber = BigInt(one), bNumber = BigInt(two);
      if (aNumber !== bNumber) return aNumber > bNumber ? 1 : -1;
    } else if (oneNumber !== twoNumber) return oneNumber ? -1 : 1;
    else return one > two ? 1 : -1;
  }
  return 0;
}

function configFromFile(file = CONFIG) {
  const source = JSON.parse(fs.readFileSync(file, "utf8"));
  if (source.schema !== 1 || !REPOSITORY.test(source.upstream) ||
    !parseVersion(source.installed) || !["stable", "prerelease"].includes(source.channel) ||
    (source.revision !== null && !/^[a-f0-9]{40}$/.test(source.revision)) ||
    !Array.isArray(source.managed) ||
    source.managed.some(value => typeof value !== "string" || !value || value.includes(".."))) {
    throw new Error("Invalid config/template.json");
  }
  return source;
}

function latestRelease(releases, channel = "stable") {
  let latest = null;
  for (const release of releases) {
    if (!release || release.draft || typeof release.tag_name !== "string") continue;
    if (channel === "stable" && release.prerelease) continue;
    const match = RELEASE_TAG.exec(release.tag_name);
    if (!match || !parseVersion(match[1])) continue;
    if (channel === "stable" && parseVersion(match[1]).prerelease.length) continue;
    if (!latest || compareVersion(match[1], latest.version) > 0) {
      latest = { version: match[1], tag: release.tag_name, url: release.html_url || null };
    }
  }
  return latest;
}

function status(config, latest) {
  if (!latest) return "unpublished";
  const difference = compareVersion(config.installed, latest.version);
  return difference < 0 ? "update-available" : difference > 0 ? "ahead" : "current";
}

async function listReleases(config, fetcher = globalThis.fetch) {
  if (typeof fetcher !== "function") throw new Error("HTTP client unavailable");
  const api = process.env.GITHUB_API_URL || "https://api.github.com";
  const endpoint = new URL(api);
  if (endpoint.protocol !== "https:" || endpoint.username || endpoint.password) throw new Error("Invalid GitHub API URL");
  const releases = [];
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  const headers = { Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "template-version-check" };
  if (token) headers.Authorization = "Bearer " + token;
  for (let page = 1; page <= MAX_PAGES; page++) {
    const url = new URL("repos/" + config.upstream + "/releases?per_page=100&page=" + page,
      api.replace(/\/+$/, "") + "/");
    const response = await fetcher(url.toString(), { headers, signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error("GitHub releases API returned HTTP " + response.status);
    const batch = await response.json();
    if (!Array.isArray(batch)) throw new Error("Unexpected GitHub releases response");
    releases.push(...batch);
    if (batch.length < 100) break;
  }
  return releases;
}

function describe(result) {
  const { config, latest, state } = result;
  const lines = [
    "### Template update status",
    "",
    "- Upstream: \`" + config.upstream + "\`",
    "- Installed Template: \`" + config.installed + "\`",
    "- Latest published Template: " + (latest ? "\`" + latest.version + "\`" : "not available"),
    "- Status: **" + state + "**",
  ];
  if (state === "update-available") lines.push("- Update available: review the upstream release and Template-owned changes before upgrading.");
  if (state === "unpublished") lines.push("- No \`template/vX.Y.Z\` release exists yet; the example software release is not a Template release.");
  if (state === "unverifiable") lines.push("- Couldn't verify upstream releases. This is advisory and does not fail CI.");
  if (latest?.url && /^https:\/\/github\.com\//.test(latest.url)) lines.push("- Release: " + latest.url);
  lines.push("", "Changes to project-owned files are never merged or overwritten automatically.");
  return lines.join("\n") + "\n";
}

async function check({ file = CONFIG, fetcher = globalThis.fetch } = {}) {
  const config = configFromFile(file);
  try {
    const latest = latestRelease(await listReleases(config, fetcher), config.channel);
    return { config, latest, state: status(config, latest) };
  } catch (error) {
    return { config, latest: null, state: "unverifiable", reason: String(error.message || error) };
  }
}

async function main(args = process.argv.slice(2)) {
  if (args.some(arg => arg !== "--json")) throw new Error("Usage: node ci/template/version.cjs [--json]");
  const result = await check();
  const report = describe(result);
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, "\n" + report);
  if (args.includes("--json")) process.stdout.write(JSON.stringify(result) + "\n");
  else process.stdout.write(report);
  if (result.reason) console.error("::warning::Template update status unavailable: " + result.reason);
}

module.exports = { parseVersion, compareVersion, configFromFile, latestRelease, status, listReleases, describe, check, main };
if (require.main === module) main().catch(error => { console.error("::error::" + error.message); process.exitCode = 1; });
