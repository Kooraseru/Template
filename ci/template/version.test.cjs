"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { parseVersion, compareVersion, latestRelease, status, check } = require("./version.cjs");

const config = { schema: 1, upstream: "Kooraseru/Template", installed: "2.0.0", revision: null,
  channel: "stable", managed: ["ci/**"] };
const make = tag_name => ({ tag_name, draft: false, prerelease: false,
  html_url: "https://github.com/Kooraseru/Template/releases/tag/" + tag_name });

test("versions compare numerically, including prereleases", () => {
  assert.ok(compareVersion("1.10.0", "1.9.9") > 0);
  assert.ok(compareVersion("1.0.0", "1.0.0-rc.9") > 0);
  assert.ok(compareVersion("1.0.0-rc.10", "1.0.0-rc.9") > 0);
  assert.equal(compareVersion("2.0.0", "2.0.0"), 0);
  assert.equal(parseVersion("template/v2.0.0"), null);
  assert.equal(parseVersion("01.0.0"), null);
});
test("template releases are distinct from project releases", () => {
  const latest = latestRelease([make("0.1.0"), make("template/v1.0.0"),
    make("template/v3.0.0"), { ...make("template/v4.0.0"), draft: true },
    { ...make("template/v3.1.0-rc.1"), prerelease: true }]);
  assert.equal(latest.version, "3.0.0");
  assert.equal(status(config, latest), "update-available");
  assert.equal(status({ ...config, installed: "3.0.0" }, latest), "current");
  assert.equal(status({ ...config, installed: "4.0.0" }, latest), "ahead");
  assert.equal(status(config, null), "unpublished");
});
test("invalid metadata fails closed, release lookups fail advisory", async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "template-version-"));
  try {
    const file = path.join(directory, "template.json");
    fs.writeFileSync(file, JSON.stringify(config));
    const current = await check({ file, fetcher: async () => ({ ok: true, json: async () => [make("template/v3.0.0")] }) });
    assert.equal(current.state, "update-available");
    const offline = await check({ file, fetcher: async () => { throw Error("offline"); } });
    assert.equal(offline.state, "unverifiable");
    fs.writeFileSync(file, JSON.stringify({ ...config, revision: "abc" }));
    await assert.rejects(check({ file }), /Invalid/);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
