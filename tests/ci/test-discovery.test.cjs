"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { discover, run } = require("../../dependencies/packages/checks/testSuites/run.cjs");

function fixture(t) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "test-suites-"));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    function write(relative, contents) {
        const file = path.join(root, relative);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, contents);
    }
    return { root, write };
}

test("suite names come from directories and benchmark cases stay opt-in", t => {
    const { root, write } = fixture(t);
    write("tests/example/suite.json", JSON.stringify({
        version: 1,
        checks: { regular: { runtime: "node", entry: "regular.cjs", timeoutSeconds: 10 } },
        benchmarks: { measure: { runtime: "node", entry: "measure.cjs", timeoutSeconds: 10 } },
    }));
    write("tests/example/regular.cjs", "require('node:fs').writeFileSync('checked', '')");
    write("tests/example/measure.cjs", "require('node:fs').writeFileSync('measured', '')");
    assert.deepEqual(discover(root).map(suite => suite.name), ["example"]);
    run({ root });
    assert.ok(fs.existsSync(path.join(root, "checked")));
    assert.ok(!fs.existsSync(path.join(root, "measured")));
    run({ root, suite: "example", benchmark: true });
    assert.ok(fs.existsSync(path.join(root, "measured")));
});

test("discovery rejects missing manifests, escaping entry points, and unbounded cases", t => {
    const { root, write } = fixture(t);
    write("tests/example/check.cjs", "");
    assert.throws(() => discover(root), /requires a regular suite.json/);
    for (const [entry, timeoutSeconds] of [["../check.cjs", 10], ["check.cjs", 0]]) {
        write("tests/example/suite.json", JSON.stringify({
            version: 1, checks: { check: { runtime: "node", entry, timeoutSeconds } },
        }));
        assert.throws(() => discover(root), /example\/check: invalid checks entry/);
    }
});
